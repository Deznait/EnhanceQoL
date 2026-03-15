#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ast
import html
import json
import pathlib
import re
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from concurrent.futures import ThreadPoolExecutor, as_completed


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_DRINKS_FILE = REPO_ROOT / "EnhanceQoL/Modules/Food/Drinks.lua"
TOOLTIP_URL = "https://nether.wowhead.com/tooltip/item/{item_id}?dataEnv={data_env}&locale={locale}"

BLOCK_START_RE = re.compile(r"^\s*addon\.Drinks\.drinkList\s*=\s*\{")
BLOCK_END_RE = re.compile(r"^\s*\}")
ENTRY_RE = re.compile(r"^(?P<indent>\s*)\{(?P<body>.*)\},(?P<suffix>\s*(--.*)?)$")
FIELD_RE = re.compile(r"^\s*(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?P<value>.+?)\s*$")
LEVEL_RE = re.compile(r"requires level\s+(\d+)", re.IGNORECASE)
PERCENT_RE = re.compile(
    r"restores\s+([0-9]+(?:[.,][0-9]+)?)%\s+of your maximum.*?mana every second over\s+(\d+)\s*sec",
    re.IGNORECASE,
)
MILLION_MANA_RE = re.compile(r"([0-9]+(?:[.,][0-9]+)?)\s+million\s+mana", re.IGNORECASE)
FLAT_MANA_RE = re.compile(r"([0-9][0-9,\.]*)\s+mana(?:\s+every\s+second)?(?:\s+over|\s+for)?\s*\d*\s*sec?", re.IGNORECASE)
FORMULA_MANA_RE = re.compile(r"(\([0-9][0-9,.\s/*+\-()]*\)|[0-9][0-9,.\s/*+\-()]*)\s+mana(?:\s+every\s+second)?(?:\s+over|\s+for)?\s*\d*\s*sec?", re.IGNORECASE)


@dataclass
class TooltipInfo:
    required_level: int | None
    mana: int
    mana_percent: float | None
    mana_duration: int | None
    is_buff_food: bool
    name: str | None = None


@dataclass
class ProbeResult:
    item_id: int
    ok: bool
    tooltip: TooltipInfo | None = None
    error: str | None = None


def safe_eval_numeric_expression(expr: str) -> int | None:
    normalized = expr.replace(",", "").strip()
    while normalized.startswith("(") and normalized.count("(") > normalized.count(")"):
        normalized = normalized[1:].strip()
    while normalized.endswith(")") and normalized.count(")") > normalized.count("("):
        normalized = normalized[:-1].strip()
    if normalized.startswith("(") and normalized.endswith(")") and normalized.count("(") == normalized.count(")"):
        normalized = normalized[1:-1].strip()
    if not normalized:
        return None
    if re.search(r"[^0-9+\-*/().\s]", normalized):
        return None

    node = ast.parse(normalized, mode="eval")

    def eval_node(current: ast.AST) -> float:
        if isinstance(current, ast.Expression):
            return eval_node(current.body)
        if isinstance(current, ast.Constant) and isinstance(current.value, (int, float)):
            return float(current.value)
        if isinstance(current, ast.UnaryOp) and isinstance(current.op, (ast.UAdd, ast.USub)):
            value = eval_node(current.operand)
            return value if isinstance(current.op, ast.UAdd) else -value
        if isinstance(current, ast.BinOp) and isinstance(current.op, (ast.Add, ast.Sub, ast.Mult, ast.Div)):
            left = eval_node(current.left)
            right = eval_node(current.right)
            if isinstance(current.op, ast.Add):
                return left + right
            if isinstance(current.op, ast.Sub):
                return left - right
            if isinstance(current.op, ast.Mult):
                return left * right
            return left / right
        raise ValueError(f"Unsupported arithmetic node: {type(current).__name__}")

    try:
        value = eval_node(node)
    except (ValueError, ZeroDivisionError, SyntaxError):
        return None
    return int(round(value))


def split_lua_fields(body: str) -> list[str]:
    parts: list[str] = []
    current: list[str] = []
    in_string = False
    escaped = False
    paren_depth = 0
    brace_depth = 0
    bracket_depth = 0

    for ch in body:
        if in_string:
            current.append(ch)
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            continue

        if ch == '"':
            in_string = True
            current.append(ch)
            continue

        if ch == "(":
            paren_depth += 1
            current.append(ch)
            continue

        if ch == ")":
            paren_depth = max(0, paren_depth - 1)
            current.append(ch)
            continue

        if ch == "{":
            brace_depth += 1
            current.append(ch)
            continue

        if ch == "}":
            brace_depth = max(0, brace_depth - 1)
            current.append(ch)
            continue

        if ch == "[":
            bracket_depth += 1
            current.append(ch)
            continue

        if ch == "]":
            bracket_depth = max(0, bracket_depth - 1)
            current.append(ch)
            continue

        if ch == "," and paren_depth == 0 and brace_depth == 0 and bracket_depth == 0:
            token = "".join(current).strip()
            if token:
                parts.append(token)
            current = []
            continue

        current.append(ch)

    tail = "".join(current).strip()
    if tail:
        parts.append(tail)
    return parts


def parse_lua_fields(body: str) -> list[tuple[str, str]]:
    parsed: list[tuple[str, str]] = []
    for token in split_lua_fields(body):
        match = FIELD_RE.match(token)
        if not match:
            raise ValueError(f"Unsupported field token: {token!r}")
        parsed.append((match.group("name"), match.group("value")))
    return parsed


def render_lua_fields(fields: list[tuple[str, str]]) -> str:
    return ", ".join(f"{name} = {value}" for name, value in fields)


def get_field(fields: list[tuple[str, str]], name: str) -> str | None:
    for key, value in fields:
        if key == name:
            return value
    return None


def remove_field(fields: list[tuple[str, str]], name: str) -> None:
    for index, (key, _) in enumerate(fields):
        if key == name:
            del fields[index]
            return


def set_field(fields: list[tuple[str, str]], name: str, value: str, *, after: str | None = None) -> None:
    for index, (key, _) in enumerate(fields):
        if key == name:
            fields[index] = (name, value)
            return

    if after:
        for index, (key, _) in enumerate(fields):
            if key == after:
                fields.insert(index + 1, (name, value))
                return
    fields.append((name, value))


def render_number(value: int | float) -> str:
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    if isinstance(value, float):
        text = f"{value:.4f}".rstrip("0").rstrip(".")
        return text
    return str(value)


def sanitize_key(name: str | None, item_id: int) -> str:
    formatted = str(name or "")
    formatted = formatted.replace('"', "").replace("'", "")
    formatted = re.sub(r"\s+", "", formatted)
    formatted = re.sub(r"[^A-Za-z0-9_-]", "", formatted)
    return formatted or f"item{item_id}"


def tooltip_to_text(raw_tooltip: str) -> str:
    text = re.sub(r"<br\s*/?>", "\n", raw_tooltip, flags=re.IGNORECASE)
    text = re.sub(r"<[^>]+>", " ", text)
    text = html.unescape(text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def parse_tooltip_payload(payload: dict) -> TooltipInfo:
    raw_tooltip = payload.get("tooltip") or ""
    text = tooltip_to_text(raw_tooltip)

    required_level = None
    level_match = LEVEL_RE.search(text)
    if level_match:
        required_level = int(level_match.group(1))

    mana = 0
    mana_percent = None
    mana_duration = None

    percent_match = PERCENT_RE.search(text)
    if percent_match:
        mana_percent = float(percent_match.group(1).replace(",", "."))
        mana_duration = int(percent_match.group(2))
    else:
        million_match = MILLION_MANA_RE.search(text)
        if million_match:
            mana = int(round(float(million_match.group(1).replace(",", ".")) * 1_000_000))
        else:
            flat_match = FLAT_MANA_RE.search(text)
            if flat_match:
                mana = int(re.sub(r"[.,]", "", flat_match.group(1)))
            else:
                formula_match = FORMULA_MANA_RE.search(text)
                if formula_match:
                    evaluated = safe_eval_numeric_expression(formula_match.group(1))
                    if evaluated is not None:
                        mana = evaluated

    is_buff_food = "well fed" in text.lower()
    return TooltipInfo(
        required_level=required_level,
        mana=mana,
        mana_percent=mana_percent,
        mana_duration=mana_duration,
        is_buff_food=is_buff_food,
        name=payload.get("name"),
    )


def fetch_tooltip(item_id: int, *, locale: int, data_env: int, timeout: float) -> TooltipInfo:
    url = TOOLTIP_URL.format(item_id=item_id, locale=locale, data_env=data_env)
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Raizor-DrinkRefresh/1.0 (+local tooling)",
            "Accept": "application/json,text/plain,*/*",
        },
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        payload = json.load(response)
    return parse_tooltip_payload(payload)


def probe_single_item(item_id: int, *, locale: int, data_env: int, timeout: float) -> ProbeResult:
    try:
        tooltip = fetch_tooltip(item_id, locale=locale, data_env=data_env, timeout=timeout)
        return ProbeResult(item_id=item_id, ok=True, tooltip=tooltip)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, ValueError) as exc:
        return ProbeResult(item_id=item_id, ok=False, error=str(exc))


def probe_items(
    item_ids: list[int],
    *,
    locale: int,
    data_env: int,
    timeout: float,
    workers: int,
) -> list[ProbeResult]:
    results_by_id: dict[int, ProbeResult] = {}
    max_workers = max(1, workers)
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {
            executor.submit(probe_single_item, item_id, locale=locale, data_env=data_env, timeout=timeout): item_id
            for item_id in item_ids
        }
        for future in as_completed(futures):
            result = future.result()
            results_by_id[result.item_id] = result
    return [results_by_id[item_id] for item_id in item_ids if item_id in results_by_id]


def parse_ids_text(raw: str) -> list[int]:
    seen: set[int] = set()
    ordered: list[int] = []
    for match in re.finditer(r"\d+", raw):
        value = int(match.group(0))
        if value in seen:
            continue
        seen.add(value)
        ordered.append(value)
    return ordered


def load_item_ids(args: argparse.Namespace) -> list[int]:
    item_ids: list[int] = []
    if args.ids:
        item_ids.extend(parse_ids_text(args.ids))
    if args.ids_file:
        item_ids.extend(parse_ids_text(args.ids_file.read_text(encoding="utf-8")))

    seen: set[int] = set()
    ordered: list[int] = []
    for item_id in item_ids:
        if item_id in seen:
            continue
        seen.add(item_id)
        ordered.append(item_id)
    return ordered


def tooltip_has_mana(tooltip: TooltipInfo) -> bool:
    return tooltip.mana > 0 or (tooltip.mana_percent is not None and tooltip.mana_percent > 0)


def render_generated_lua_entry(tooltip: TooltipInfo, item_id: int) -> str:
    fields: list[tuple[str, str]] = [
        ("key", f'"{sanitize_key(tooltip.name, item_id)}"'),
        ("id", str(item_id)),
        ("requiredLevel", str(tooltip.required_level or 1)),
        ("mana", str(tooltip.mana)),
    ]
    if tooltip.mana_percent is not None:
        fields.append(("manaPercent", render_number(tooltip.mana_percent)))
    if tooltip.mana_duration is not None:
        fields.append(("manaDuration", str(tooltip.mana_duration)))
    fields.append(("isBuffFood", "true" if tooltip.is_buff_food else "false"))
    return "{ " + render_lua_fields(fields) + " },"


def write_probe_outputs(
    results: list[ProbeResult],
    *,
    output_json: pathlib.Path | None,
    output_lua: pathlib.Path | None,
    include_no_mana: bool,
) -> tuple[int, int, int]:
    ok_results = [result for result in results if result.ok and result.tooltip is not None]
    error_results = [result for result in results if not result.ok]
    mana_results = [result for result in ok_results if tooltip_has_mana(result.tooltip)]
    no_mana_results = [result for result in ok_results if not tooltip_has_mana(result.tooltip)]

    if output_json:
        payload = []
        for result in results:
            if result.ok and result.tooltip is not None:
                payload.append(
                    {
                        "item_id": result.item_id,
                        "ok": True,
                        "name": result.tooltip.name,
                        "required_level": result.tooltip.required_level,
                        "mana": result.tooltip.mana,
                        "mana_percent": result.tooltip.mana_percent,
                        "mana_duration": result.tooltip.mana_duration,
                        "is_buff_food": result.tooltip.is_buff_food,
                        "has_mana": tooltip_has_mana(result.tooltip),
                    }
                )
            else:
                payload.append({"item_id": result.item_id, "ok": False, "error": result.error})
        output_json.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    if output_lua:
        emitted = mana_results if not include_no_mana else ok_results
        lines = []
        for result in emitted:
            tooltip = result.tooltip
            if tooltip is None:
                continue
            if not include_no_mana and not tooltip_has_mana(tooltip):
                continue
            lines.append(render_generated_lua_entry(tooltip, result.item_id))
        output_lua.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")

    return len(mana_results), len(no_mana_results), len(error_results)


def update_entry_line(line: str, tooltip: TooltipInfo) -> str:
    match = ENTRY_RE.match(line)
    if not match:
        return line

    fields = parse_lua_fields(match.group("body"))

    if tooltip.required_level is not None:
        set_field(fields, "requiredLevel", render_number(tooltip.required_level))
    set_field(fields, "mana", render_number(tooltip.mana))
    set_field(fields, "isBuffFood", "true" if tooltip.is_buff_food else "false")

    if tooltip.mana_percent is not None:
        set_field(fields, "manaPercent", render_number(tooltip.mana_percent), after="mana")
        if tooltip.mana_duration is not None:
            set_field(fields, "manaDuration", render_number(tooltip.mana_duration), after="manaPercent")
        else:
            remove_field(fields, "manaDuration")
    else:
        remove_field(fields, "manaPercent")
        remove_field(fields, "manaDuration")

    new_body = render_lua_fields(fields)
    return f"{match.group('indent')}{{ {new_body} }},{match.group('suffix')}"


def refresh_drinks_file(
    drinks_file: pathlib.Path,
    *,
    locale: int,
    data_env: int,
    timeout: float,
    sleep_seconds: float,
    limit_ids: set[int] | None,
) -> tuple[str, list[str], list[str]]:
    lines = drinks_file.read_text(encoding="utf-8").splitlines()

    in_block = False
    updated_lines: list[str] = []
    changed: list[str] = []
    failed: list[str] = []

    for line_number, line in enumerate(lines, start=1):
        if BLOCK_START_RE.match(line):
            in_block = True
            updated_lines.append(line)
            continue

        if in_block and BLOCK_END_RE.match(line):
            in_block = False
            updated_lines.append(line)
            continue

        if not in_block:
            updated_lines.append(line)
            continue

        match = ENTRY_RE.match(line)
        if not match:
            updated_lines.append(line)
            continue

        fields = parse_lua_fields(match.group("body"))
        id_value = get_field(fields, "id")
        if id_value is None:
            updated_lines.append(line)
            continue

        try:
            item_id = int(id_value)
        except ValueError:
            updated_lines.append(line)
            continue

        if limit_ids and item_id not in limit_ids:
            updated_lines.append(line)
            continue

        if get_field(fields, "isSpell") == "true":
            updated_lines.append(line)
            continue

        try:
            tooltip = fetch_tooltip(item_id, locale=locale, data_env=data_env, timeout=timeout)
            new_line = update_entry_line(line, tooltip)
            updated_lines.append(new_line)
            if new_line != line:
                changed.append(f"line {line_number}: item {item_id}")
            if sleep_seconds > 0:
                time.sleep(sleep_seconds)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, ValueError) as exc:
            failed.append(f"line {line_number}: item {item_id}: {exc}")
            updated_lines.append(line)

    return "\n".join(updated_lines) + "\n", changed, failed


def self_test() -> int:
    sample_payload = {
        "name": "Royal Roast",
        "quality": 3,
        "icon": "inv_cooking_100_roastduck",
        "tooltip": (
            "<table><tr><td><b class=\"q3\">Royal Roast</b></td></tr></table>"
            "<table><tr><td><span class=\"q2\">Use: Restores 7% of your maximum health and mana every second over 20 sec. "
            "Must remain seated while eating.<br /><br /><span style=\"color:#FFFFFF\">Well Fed</span><br />"
            "Requires Level 90</span></td></tr></table>"
        ),
    }
    info = parse_tooltip_payload(sample_payload)
    assert info.required_level == 90
    assert info.mana == 0
    assert info.mana_percent == 7
    assert info.mana_duration == 20
    assert info.is_buff_food is True

    flat_payload = {
        "name": "Sipping Aether",
        "tooltip": "Restores 35,000 health and 30,000 mana over 20 sec. Must remain seated while eating. Requires Level 75",
    }
    flat_info = parse_tooltip_payload(flat_payload)
    assert flat_info.required_level == 75
    assert flat_info.mana == 30000
    assert flat_info.mana_percent is None
    assert flat_info.mana_duration is None
    assert flat_info.is_buff_food is False

    formula_payload = {
        "name": "Sipping Aether",
        "tooltip": (
            'Use: Restores (8750 / 5 * 20) health and (7500 / 5 * 20) mana over 20 sec. '
            "Must remain seated while eating. Requires Level 75"
        ),
    }
    formula_info = parse_tooltip_payload(formula_payload)
    assert formula_info.required_level == 75
    assert formula_info.mana == 30000
    assert formula_info.mana_percent is None
    assert formula_info.mana_duration is None
    assert formula_info.is_buff_food is False

    line = '\t{ key = "RoyalRoast", id = 242275, requiredLevel = 90, mana = 0, manaPercent = 7, manaDuration = 20, isBuffFood = true },'
    rewritten = update_entry_line(line, flat_info)
    assert "mana = 30000" in rewritten
    assert "manaPercent" not in rewritten
    assert "isBuffFood = false" in rewritten
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Refresh EnhanceQoL drink entries from Wowhead tooltip JSON.")
    parser.add_argument("--file", type=pathlib.Path, default=DEFAULT_DRINKS_FILE, help="Path to Drinks.lua")
    parser.add_argument("--output", type=pathlib.Path, help="Write the refreshed Lua file to this path")
    parser.add_argument("--write", action="store_true", help="Overwrite the input file in place")
    parser.add_argument("--locale", type=int, default=0, help="Wowhead locale id, default: 0 (enUS)")
    parser.add_argument("--data-env", type=int, default=1, help="Wowhead dataEnv query parameter")
    parser.add_argument("--timeout", type=float, default=10.0, help="HTTP timeout in seconds")
    parser.add_argument("--sleep", type=float, default=0.0, help="Sleep between requests in seconds")
    parser.add_argument("--ids", help="Comma-separated subset of item ids to refresh")
    parser.add_argument("--ids-file", type=pathlib.Path, help="File containing ids to probe")
    parser.add_argument("--show-failures", action="store_true", help="Print failed item fetches")
    parser.add_argument("--probe-output-json", type=pathlib.Path, help="Write raw probe results as JSON")
    parser.add_argument("--probe-output-lua", type=pathlib.Path, help="Write generated Lua entries for the probed ids")
    parser.add_argument("--include-no-mana", action="store_true", help="Include probed ids without mana data in Lua output")
    parser.add_argument("--workers", type=int, default=12, help="Concurrent workers for probe mode")
    parser.add_argument("--self-test", action="store_true", help="Run offline parser tests and exit")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.self_test:
        return self_test()

    item_ids = load_item_ids(args)
    limit_ids = set(item_ids) if item_ids else None

    if args.probe_output_json or args.probe_output_lua:
        if not item_ids:
            print("Probe mode requires --ids or --ids-file.", file=sys.stderr)
            return 2
        results = probe_items(
            item_ids,
            locale=args.locale,
            data_env=args.data_env,
            timeout=args.timeout,
            workers=args.workers,
        )
        mana_count, no_mana_count, error_count = write_probe_outputs(
            results,
            output_json=args.probe_output_json,
            output_lua=args.probe_output_lua,
            include_no_mana=args.include_no_mana,
        )
        print(f"Probed ids: {len(results)}")
        print(f"Entries with mana data: {mana_count}")
        print(f"Entries without mana data: {no_mana_count}")
        print(f"Errors: {error_count}")
        if args.show_failures:
            for result in results:
                if not result.ok:
                    print(f"item {result.item_id}: {result.error}")
        return 1 if error_count else 0

    refreshed_text, changed, failed = refresh_drinks_file(
        args.file,
        locale=args.locale,
        data_env=args.data_env,
        timeout=args.timeout,
        sleep_seconds=args.sleep,
        limit_ids=limit_ids,
    )

    if args.write and args.output:
        print("Use either --write or --output, not both.", file=sys.stderr)
        return 2

    if args.write:
        args.file.write_text(refreshed_text, encoding="utf-8")
        print(f"Wrote refreshed data to {args.file}")
    elif args.output:
        args.output.write_text(refreshed_text, encoding="utf-8")
        print(f"Wrote refreshed data to {args.output}")
    else:
        print(f"Prepared refreshed content for {args.file}")

    print(f"Changed entries: {len(changed)}")
    if failed:
        print(f"Failed entries: {len(failed)}")
        if args.show_failures:
            for failure in failed:
                print(failure)

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
