local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.Aura = addon.Aura or {}
addon.Aura.UF = addon.Aura.UF or {}
local UF = addon.Aura.UF
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")

UF.GlobalAuraIgnore = UF.GlobalAuraIgnore or {}
local GAI = UF.GlobalAuraIgnore

local ipairs = ipairs
local pairs = pairs
local next = next
local tostring = tostring
local tonumber = tonumber
local tinsert = table.insert
local sort = table.sort
local wipe = _G.wipe or (table and table.wipe)
local issecretvalue = _G.issecretvalue
local LOCALIZED_CLASS_NAMES_MALE = _G.LOCALIZED_CLASS_NAMES_MALE or {}
local LOCALIZED_CLASS_NAMES_FEMALE = _G.LOCALIZED_CLASS_NAMES_FEMALE or {}

local UNIT_CONTEXT_ORDER = {
	"player",
	"target",
	"focus",
	"party",
	"raid",
}

local UNIT_CONTEXT_LOOKUP = {
	player = true,
	target = true,
	focus = true,
	party = true,
	raid = true,
}

local DEFAULT_EDITOR_CONTEXT = "party"

local DEFAULT_SPECIAL_DEBUFFS = {
	satedExhaustion = true,
	deserter = true,
}

local SPECIAL_DEBUFF_GROUPS = {
	{
		key = "satedExhaustion",
		labelKey = "UFGlobalAuraIgnoreSatedExhaustion",
		fallbackLabel = "Sated/Exhaustion Debuffs",
		spellIds = { 57723, 57724, 80354, 95809, 160455, 264689, 390435 },
	},
	{
		key = "deserter",
		labelKey = "UFGlobalAuraIgnoreDeserter",
		fallbackLabel = "Deserter Debuffs",
		spellIds = { 26013, 71041 },
	},
}

local SPECIAL_DEBUFF_SETS = {}
for i = 1, #SPECIAL_DEBUFF_GROUPS do
	local group = SPECIAL_DEBUFF_GROUPS[i]
	local set = {}
	for j = 1, #(group.spellIds or {}) do
		local spellId = tonumber(group.spellIds[j])
		if spellId and spellId > 0 then set[spellId] = true end
	end
	SPECIAL_DEBUFF_SETS[group.key] = set
end

local editorFrame
local familyEntryList
local familyEntryById

local function tr(key, fallback)
	local value = L and L[key]
	if value == nil or value == "" then return fallback or key end
	return value
end

local function copyTable(src)
	if type(src) ~= "table" then return src end
	if addon.functions and addon.functions.copyTable then return addon.functions.copyTable(src) end
	if CopyTable then return CopyTable(src) end
	local out = {}
	for key, value in pairs(src) do
		if type(value) == "table" then
			out[key] = copyTable(value)
		else
			out[key] = value
		end
	end
	return out
end

local function wipeTable(tbl)
	if not tbl then return end
	if wipe then
		wipe(tbl)
	else
		for key in pairs(tbl) do
			tbl[key] = nil
		end
	end
end

local function getSpellName(spellId)
	if spellId == nil then return nil end
	if C_Spell and C_Spell.GetSpellName then
		local name = C_Spell.GetSpellName(spellId)
		if type(name) == "string" and name ~= "" then return name end
	end
	if GetSpellInfo then
		local name = GetSpellInfo(spellId)
		if type(name) == "string" and name ~= "" then return name end
	end
	return nil
end

local function getClassLabel(classToken)
	if classToken and classToken ~= "" then
		if LOCALIZED_CLASS_NAMES_MALE[classToken] then return LOCALIZED_CLASS_NAMES_MALE[classToken] end
		if LOCALIZED_CLASS_NAMES_FEMALE[classToken] then return LOCALIZED_CLASS_NAMES_FEMALE[classToken] end
		return tostring(classToken)
	end
	return tr("UFGroupHealerBuffEditorClassOther", "Other")
end

local function getUnitContextLabel(context)
	if context == "player" then return PLAYER or "Player" end
	if context == "target" then return TARGET or "Target" end
	if context == "focus" then return FOCUS or "Focus" end
	if context == "party" then return PARTY or "Party" end
	if context == "raid" then return RAID or "Raid" end
	return tostring(context or "")
end

local function getFamilyFromSpell(spellId)
	local hb = UF and UF.GroupFramesHealerBuffs
	if hb and hb.GetFamilyFromSpell then return hb.GetFamilyFromSpell(spellId) end
	return nil
end

local function buildFamilyEntries()
	local hb = UF and UF.GroupFramesHealerBuffs
	if not (hb and hb.FAMILY_ORDER and hb.FAMILY_BY_ID) then return {}, {} end

	local entries = {}
	local byId = {}
	local classBuckets = {}
	local classOrder = {}
	local classSeen = {}
	local helper = UF and UF.GroupFramesHelper
	local preferredClassOrder = (helper and helper.CLASS_TOKENS) or {}

	for i = 1, #preferredClassOrder do
		local token = preferredClassOrder[i]
		if token and not classSeen[token] then
			classSeen[token] = true
			classOrder[#classOrder + 1] = token
		end
	end

	local function ensureBucket(token)
		token = token or "OTHER"
		if not classBuckets[token] then classBuckets[token] = {} end
		if not classSeen[token] then
			classSeen[token] = true
			classOrder[#classOrder + 1] = token
		end
		return classBuckets[token]
	end

	for i = 1, #hb.FAMILY_ORDER do
		local familyId = hb.FAMILY_ORDER[i]
		local family = hb.FAMILY_BY_ID[familyId]
		if family then
			local spellIds = {}
			local rawSpellIds = family.spellIds or {}
			for j = 1, #rawSpellIds do
				local spellId = tonumber(rawSpellIds[j])
				if spellId and spellId > 0 then spellIds[#spellIds + 1] = spellId end
			end
			local primarySpellId = spellIds[1]
			local resolvedName = getSpellName(primarySpellId) or family.fallbackName or family.id or tostring(familyId)
			local specPrefix = family.spec and family.spec ~= "" and (tostring(family.spec) .. ": ") or ""
			local label = string.format("%s%s", specPrefix, tostring(resolvedName))
			local entry = {
				familyId = tostring(familyId),
				classToken = family.classToken or "OTHER",
				classLabel = getClassLabel(family.classToken),
				label = label,
				spellIds = spellIds,
			}
			tinsert(ensureBucket(entry.classToken), entry)
			byId[entry.familyId] = entry
		end
	end

	local sortedClassOrder = {}
	for i = 1, #classOrder do
		local token = classOrder[i]
		if classBuckets[token] and #classBuckets[token] > 0 then sortedClassOrder[#sortedClassOrder + 1] = token end
	end
	for token, bucket in pairs(classBuckets) do
		if #bucket > 0 then
			local present = false
			for i = 1, #sortedClassOrder do
				if sortedClassOrder[i] == token then
					present = true
					break
				end
			end
			if not present then sortedClassOrder[#sortedClassOrder + 1] = token end
		end
	end

	sort(sortedClassOrder, function(a, b)
		local aIdx = nil
		local bIdx = nil
		for i = 1, #classOrder do
			if aIdx == nil and classOrder[i] == a then aIdx = i end
			if bIdx == nil and classOrder[i] == b then bIdx = i end
		end
		if aIdx and bIdx then return aIdx < bIdx end
		if aIdx then return true end
		if bIdx then return false end
		return tostring(a) < tostring(b)
	end)

	for i = 1, #sortedClassOrder do
		local token = sortedClassOrder[i]
		local bucket = classBuckets[token]
		tinsert(entries, {
			isHeader = true,
			classToken = token,
			label = getClassLabel(token),
		})
		sort(bucket, function(a, b) return tostring(a.label) < tostring(b.label) end)
		for j = 1, #bucket do
			tinsert(entries, bucket[j])
		end
	end

	return entries, byId
end

local function getFamilyEntries()
	if not familyEntryList then
		familyEntryList, familyEntryById = buildFamilyEntries()
	end
	return familyEntryList, familyEntryById
end

local function createDefaultSpecialDebuffs()
	local out = {}
	for key, defaultValue in pairs(DEFAULT_SPECIAL_DEBUFFS) do
		out[key] = defaultValue == true
	end
	return out
end

local function createDefaultConfig()
	local function createDefaultBucket()
		return {
			ignoredFamilies = {},
			ignoredSpells = {},
			specialDebuffs = createDefaultSpecialDebuffs(),
		}
	end

	return {
		enabled = false,
		version = 1,
		byContext = {
			party = createDefaultBucket(),
			raid = createDefaultBucket(),
		},
	}
end

GAI.CreateDefaultConfig = createDefaultConfig

local function hasAnyEnabledValues(map)
	if type(map) ~= "table" then return false end
	for _, value in pairs(map) do
		if value == true then return true end
	end
	return false
end

local function normalizeFamilySet(source, knownById)
	local out = {}
	if type(source) ~= "table" then return out end
	for key, value in pairs(source) do
		if value == true then
			local familyId = tostring(key)
			if not knownById or knownById[familyId] then out[familyId] = true end
		end
	end
	return out
end

local function normalizeSpellSet(source)
	local out = {}
	if type(source) ~= "table" then return out end
	for key, value in pairs(source) do
		local spellId
		if value == true or value == 1 then
			spellId = tonumber(key)
		elseif type(value) == "number" then
			spellId = tonumber(value)
		end
		if spellId and spellId > 0 then out[spellId] = true end
	end
	return out
end

local function normalizeSpecialSet(source)
	local out = {}
	for key, defaultValue in pairs(DEFAULT_SPECIAL_DEBUFFS) do
		if type(source) == "table" then
			if source[key] == nil then
				out[key] = defaultValue == true
			else
				out[key] = source[key] == true
			end
		else
			out[key] = defaultValue == true
		end
	end
	return out
end

local function normalizeContextBucket(cfg, context, knownById)
	context = GAI.ResolveContext(context) or context
	if not UNIT_CONTEXT_LOOKUP[context] then return nil end
	cfg.byContext = type(cfg.byContext) == "table" and cfg.byContext or {}
	local bucket = cfg.byContext[context]
	if type(bucket) ~= "table" then bucket = {} end
	bucket.ignoredFamilies = normalizeFamilySet(bucket.ignoredFamilies, knownById)
	bucket.ignoredSpells = normalizeSpellSet(bucket.ignoredSpells)
	bucket.specialDebuffs = normalizeSpecialSet(bucket.specialDebuffs)
	cfg.byContext[context] = bucket
	return bucket
end

local function getContextBucket(cfg, context)
	context = GAI.ResolveContext(context) or context
	if not UNIT_CONTEXT_LOOKUP[context] then return nil end
	cfg.byContext = type(cfg.byContext) == "table" and cfg.byContext or {}
	local bucket = cfg.byContext[context]
	if type(bucket) ~= "table" then
		bucket = {
			ignoredFamilies = {},
			ignoredSpells = {},
			specialDebuffs = createDefaultSpecialDebuffs(),
		}
		cfg.byContext[context] = bucket
		return bucket
	end
	if type(bucket.ignoredFamilies) ~= "table" then bucket.ignoredFamilies = {} end
	if type(bucket.ignoredSpells) ~= "table" then bucket.ignoredSpells = {} end
	if type(bucket.specialDebuffs) ~= "table" then
		bucket.specialDebuffs = createDefaultSpecialDebuffs()
	else
		for key, defaultValue in pairs(DEFAULT_SPECIAL_DEBUFFS) do
			if bucket.specialDebuffs[key] == nil then bucket.specialDebuffs[key] = defaultValue == true end
		end
	end
	return bucket
end

local function normalizeConfig(cfg)
	if type(cfg) ~= "table" then cfg = createDefaultConfig() end
	cfg.enabled = cfg.enabled == true
	cfg.version = tonumber(cfg.version) or 1
	cfg.byContext = type(cfg.byContext) == "table" and cfg.byContext or {}

	local _, byId = getFamilyEntries()
	if cfg._eqolContextMigrated ~= true then
		local legacyFamilies = normalizeFamilySet(cfg.ignoredFamilies, byId)
		local legacySpells = normalizeSpellSet(cfg.ignoredSpells)
		local legacySpecial = normalizeSpecialSet(cfg.specialDebuffs)
		local hasLegacyValues = hasAnyEnabledValues(legacyFamilies) or hasAnyEnabledValues(legacySpells) or hasAnyEnabledValues(legacySpecial)
		if hasLegacyValues then
			local targetContexts = {}
			if type(cfg.applyTo) == "table" then
				for i = 1, #UNIT_CONTEXT_ORDER do
					local context = UNIT_CONTEXT_ORDER[i]
					if cfg.applyTo[context] == true then targetContexts[#targetContexts + 1] = context end
				end
			end
			if #targetContexts == 0 then
				for i = 1, #UNIT_CONTEXT_ORDER do
					targetContexts[#targetContexts + 1] = UNIT_CONTEXT_ORDER[i]
				end
			end
			for i = 1, #targetContexts do
				local context = targetContexts[i]
				local bucket = type(cfg.byContext[context]) == "table" and cfg.byContext[context] or {}
				bucket.ignoredFamilies = type(bucket.ignoredFamilies) == "table" and bucket.ignoredFamilies or {}
				bucket.ignoredSpells = type(bucket.ignoredSpells) == "table" and bucket.ignoredSpells or {}
				bucket.specialDebuffs = normalizeSpecialSet(bucket.specialDebuffs)
				for familyId in pairs(legacyFamilies) do
					bucket.ignoredFamilies[familyId] = true
				end
				for spellId in pairs(legacySpells) do
					bucket.ignoredSpells[spellId] = true
				end
				for specialKey, enabled in pairs(legacySpecial) do
					if enabled == true then bucket.specialDebuffs[specialKey] = true end
				end
				cfg.byContext[context] = bucket
			end
		end
		cfg._eqolContextMigrated = true
	end

	for i = 1, #UNIT_CONTEXT_ORDER do
		normalizeContextBucket(cfg, UNIT_CONTEXT_ORDER[i], byId)
	end
	for key in pairs(cfg.byContext) do
		if not UNIT_CONTEXT_LOOKUP[key] then cfg.byContext[key] = nil end
	end
	if cfg._eqolSpecialDefaultsV2 ~= true then
		for i = 1, #UNIT_CONTEXT_ORDER do
			local bucket = getContextBucket(cfg, UNIT_CONTEXT_ORDER[i])
			if bucket and type(bucket.specialDebuffs) == "table" then
				bucket.specialDebuffs.satedExhaustion = true
				bucket.specialDebuffs.deserter = true
			end
		end
		cfg._eqolSpecialDefaultsV2 = true
	end

	-- Legacy fields: normalized into byContext above.
	cfg.applyTo = nil
	cfg.ignoredFamilies = nil
	cfg.ignoredSpells = nil
	cfg.specialDebuffs = nil

	cfg._eqolNormalized = true
	return cfg
end

function GAI.EnsureConfig()
	addon.db = addon.db or {}
	if type(addon.db.ufGlobalAuraIgnore) ~= "table" then addon.db.ufGlobalAuraIgnore = createDefaultConfig() end
	addon.db.ufGlobalAuraIgnore = normalizeConfig(addon.db.ufGlobalAuraIgnore)
	return addon.db.ufGlobalAuraIgnore
end

function GAI.ResolveContext(context)
	local key = tostring(context or ""):lower()
	if key == "" then return nil end
	if key == "party" or key:match("^party%d+$") then return "party" end
	if key == "raid" or key == "mt" or key == "ma" or key:match("^raid%d+$") then return "raid" end
	if key == "player" or key == "pet" or key == "vehicle" then return "player" end
	if key == "focus" then return "focus" end
	if key == "target" or key == "targettarget" or key:match("^boss%d+$") then return "target" end
	return nil
end

function GAI.ShouldIgnoreSpell(context, spellId, cfgOverride)
	if spellId == nil then return false end
	if issecretvalue and issecretvalue(spellId) then return false end
	spellId = tonumber(spellId)
	if not spellId or spellId <= 0 then return false end
	local cfg = cfgOverride
	if type(cfg) ~= "table" then
		cfg = addon.db and addon.db.ufGlobalAuraIgnore
		if type(cfg) ~= "table" then cfg = GAI.EnsureConfig() end
	end
	if cfg._eqolNormalized ~= true then cfg = normalizeConfig(cfg) end
	if cfg.enabled ~= true then return false end

	local resolvedContext = GAI.ResolveContext(context)
	if not resolvedContext then return false end
	local bucket = getContextBucket(cfg, resolvedContext)
	if not bucket then return false end

	if bucket.ignoredSpells[spellId] == true then return true end

	for i = 1, #SPECIAL_DEBUFF_GROUPS do
		local group = SPECIAL_DEBUFF_GROUPS[i]
		if bucket.specialDebuffs[group.key] == true and SPECIAL_DEBUFF_SETS[group.key] and SPECIAL_DEBUFF_SETS[group.key][spellId] == true then return true end
	end

	local familyId = getFamilyFromSpell(spellId)
	if familyId and bucket.ignoredFamilies[tostring(familyId)] == true then return true end
	return false
end

function GAI.ShouldIgnoreAura(context, aura, cfgOverride)
	if type(aura) ~= "table" then return false end
	local spellId = aura.spellId
	if spellId == nil then spellId = aura.spellID end
	if spellId == nil then return false end
	return GAI.ShouldIgnoreSpell(context, spellId, cfgOverride)
end

local function requestAuraRefresh()
	if InCombatLockdown and InCombatLockdown() then return end

	if UF and UF.FullScanTargetAuras then
		UF.FullScanTargetAuras("player")
		UF.FullScanTargetAuras("target")
		UF.FullScanTargetAuras("focus")
		for i = 1, 5 do
			UF.FullScanTargetAuras("boss" .. tostring(i))
		end
	end

	local gf = UF and UF.GroupFrames
	if gf then
		if gf.Refresh then gf.Refresh() end
		if gf.RefreshHealerBuffPlacement then gf:RefreshHealerBuffPlacement() end
	end
end

GAI.RequestAuraRefresh = requestAuraRefresh

local function createCheck(parent, text, width)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	if check.Text then
		check.Text:SetText(text or "")
		check.Text:SetTextColor(1, 1, 1, 1)
		if width then
			check.Text:SetWidth(width)
			check.Text:SetJustifyH("LEFT")
		end
	end
	return check
end

local function applyBackdrop(frame)
	if not frame then return end
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 32,
		edgeSize = 24,
		insets = { left = 6, right = 6, top = 6, bottom = 6 },
	})
	frame:SetBackdropColor(0, 0, 0, 1)
end

local function updateCheckEnabledVisual(check, enabled)
	if not check then return end
	if check.Text and check.Text.SetTextColor then
		if enabled then
			check.Text:SetTextColor(1, 1, 1, 1)
		else
			check.Text:SetTextColor(0.6, 0.6, 0.6, 1)
		end
	end
	if check.SetAlpha then check:SetAlpha(enabled and 1 or 0.9) end
end

local function rebuildFamilyRows(frame)
	if not frame or not frame.ScrollContent then return end

	for i = 1, #(frame._dynamicRows or {}) do
		local row = frame._dynamicRows[i]
		if row and row.Hide then row:Hide() end
	end
	frame._dynamicRows = frame._dynamicRows or {}
	wipeTable(frame._dynamicRows)
	frame.FamilyRows = frame.FamilyRows or {}
	wipeTable(frame.FamilyRows)

	local entries = getFamilyEntries()
	local anchorParent = frame.ScrollContent
	local y = -6
	local rowWidth = (frame.ScrollFrame and frame.ScrollFrame:GetWidth() or 500) - 30
	if rowWidth < 120 then rowWidth = 120 end
	local previousWasHeader = true

	for i = 1, #entries do
		local entry = entries[i]
		if entry.isHeader then
			if i > 1 and not previousWasHeader then y = y - 8 end
			local header = anchorParent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			header:SetPoint("TOPLEFT", anchorParent, "TOPLEFT", 6, y)
			header:SetText(entry.label or "")
			header:SetTextColor(1, 0.85, 0.2, 1)
			tinsert(frame._dynamicRows, header)
			y = y - 20
			previousWasHeader = true
		else
			local check = createCheck(anchorParent, entry.label or "", rowWidth)
			check:SetPoint("TOPLEFT", anchorParent, "TOPLEFT", 4, y)
			check._familyId = entry.familyId
			check._entry = entry
			check:SetScript("OnClick", function(self)
				local cfg = GAI.EnsureConfig()
				local context = (frame and frame._selectedContext) or DEFAULT_EDITOR_CONTEXT
				local bucket = getContextBucket(cfg, context)
				if not bucket then return end
				local familyId = tostring(self._familyId or "")
				if familyId == "" then return end
				if self:GetChecked() then
					bucket.ignoredFamilies[familyId] = true
				else
					bucket.ignoredFamilies[familyId] = nil
				end
				normalizeConfig(cfg)
				requestAuraRefresh()
				GAI:RefreshEditor()
			end)
			check:SetScript("OnEnter", function(self)
				if not GameTooltip then return end
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:AddLine(self._entry.label or "", 1, 0.82, 0)
				GameTooltip:Show()
			end)
			check:SetScript("OnLeave", function()
				if GameTooltip then GameTooltip:Hide() end
			end)
			tinsert(frame._dynamicRows, check)
			tinsert(frame.FamilyRows, check)
			y = y - 22
			previousWasHeader = false
		end
	end

	y = y - 8
	local contentHeight = -y
	if contentHeight < 1 then contentHeight = 1 end
	frame.ScrollContent:SetHeight(contentHeight)
end

local function buildEditor()
	if editorFrame then return editorFrame end

	local frame = CreateFrame("Frame", "EQOL_UF_GlobalAuraIgnoreEditor", UIParent, "BackdropTemplate")
	frame:SetSize(620, 650)
	applyBackdrop(frame)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetFrameStrata("TOOLTIP")
	frame:SetClampedToScreen(true)
	frame:SetPoint("CENTER")
	frame:Hide()

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(tr("UFGlobalAuraIgnoreEditorTitle", "Global Aura Ignore"))
	frame.Title = title

	local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	subtitle:SetText(tr("UFGlobalAuraIgnoreEditorSubtitle", "Ignore selected auras per frame (Player/Target/Focus/Party/Raid)."))
	subtitle:SetWidth(570)
	subtitle:SetJustifyH("LEFT")
	frame.Subtitle = subtitle

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)
	close:SetScript("OnClick", function() frame:Hide() end)
	frame.CloseButton = close

	local enabledCheck = createCheck(frame, tr("UFGlobalAuraIgnoreEditorEnabled", "Enable global aura ignore"), 420)
	enabledCheck:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -4, -14)
	enabledCheck:SetScript("OnClick", function(self)
		local cfg = GAI.EnsureConfig()
		cfg.enabled = self:GetChecked() == true
		normalizeConfig(cfg)
		requestAuraRefresh()
		GAI:RefreshEditor()
	end)
	frame.EnabledCheck = enabledCheck

	local contextLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	contextLabel:SetPoint("TOPLEFT", enabledCheck, "BOTTOMLEFT", 4, -12)
	contextLabel:SetText(tr("UFGlobalAuraIgnoreEditorContext", "Frame"))
	frame.ContextLabel = contextLabel

	frame.ContextButtons = {}
	local previousContextButton
	for i = 1, #UNIT_CONTEXT_ORDER do
		local key = UNIT_CONTEXT_ORDER[i]
		local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		button:SetSize(88, 20)
		button._contextKey = key
		button._label = getUnitContextLabel(key)
		button:SetText(button._label)
		if i == 1 then
			button:SetPoint("TOPLEFT", contextLabel, "BOTTOMLEFT", -2, -6)
		else
			button:SetPoint("LEFT", previousContextButton, "RIGHT", 6, 0)
		end
		button:SetScript("OnClick", function(self)
			frame._selectedContext = self._contextKey
			GAI:RefreshEditor()
		end)
		frame.ContextButtons[key] = button
		previousContextButton = button
	end
	frame._selectedContext = frame._selectedContext or DEFAULT_EDITOR_CONTEXT

	local specialLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	specialLabel:SetPoint("TOPLEFT", contextLabel, "BOTTOMLEFT", 0, -34)
	specialLabel:SetText(tr("UFGlobalAuraIgnoreEditorSpecial", "Special debuff categories"))
	frame.SpecialLabel = specialLabel

	frame.SpecialChecks = {}
	local previousSpecial
	for i = 1, #SPECIAL_DEBUFF_GROUPS do
		local group = SPECIAL_DEBUFF_GROUPS[i]
		local label = tr(group.labelKey, group.fallbackLabel)
		local check = createCheck(frame, label, 570)
		if i == 1 then
			check:SetPoint("TOPLEFT", specialLabel, "BOTTOMLEFT", -4, -8)
		else
			check:SetPoint("TOPLEFT", previousSpecial, "BOTTOMLEFT", 0, -4)
		end
		check._groupKey = group.key
		check:SetScript("OnClick", function(self)
			local cfg = GAI.EnsureConfig()
			local context = (frame and frame._selectedContext) or DEFAULT_EDITOR_CONTEXT
			local bucket = getContextBucket(cfg, context)
			if not bucket then return end
			bucket.specialDebuffs[self._groupKey] = self:GetChecked() == true
			normalizeConfig(cfg)
			requestAuraRefresh()
			GAI:RefreshEditor()
		end)
		frame.SpecialChecks[group.key] = check
		previousSpecial = check
	end

	local listLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	listLabel:SetPoint("TOPLEFT", previousSpecial, "BOTTOMLEFT", 4, -12)
	listLabel:SetText(tr("UFGlobalAuraIgnoreEditorFamilies", "Healer buff spell families"))
	frame.ListLabel = listLabel

	local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", listLabel, "BOTTOMLEFT", -4, -6)
	scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 20)
	frame.ScrollFrame = scrollFrame

	local scrollContent = CreateFrame("Frame", nil, scrollFrame)
	scrollContent:SetSize(1, 1)
	scrollFrame:SetScrollChild(scrollContent)
	frame.ScrollContent = scrollContent
	frame.FamilyRows = {}
	frame._dynamicRows = {}

	rebuildFamilyRows(frame)

	frame:SetScript("OnShow", function() GAI:RefreshEditor() end)

	editorFrame = frame
	return frame
end

function GAI:RefreshEditor()
	local frame = editorFrame
	if not frame then return end
	local cfg = GAI.EnsureConfig()
	if not cfg then return end

	if frame.EnabledCheck then frame.EnabledCheck:SetChecked(cfg.enabled == true) end

	local selectedContext = frame._selectedContext
	if not UNIT_CONTEXT_LOOKUP[selectedContext] then
		selectedContext = DEFAULT_EDITOR_CONTEXT
		frame._selectedContext = selectedContext
	end
	local bucket = getContextBucket(cfg, selectedContext)
	if not bucket then return end

	for i = 1, #UNIT_CONTEXT_ORDER do
		local key = UNIT_CONTEXT_ORDER[i]
		local button = frame.ContextButtons and frame.ContextButtons[key]
		if button then
			local isSelected = key == selectedContext
			local label = button._label or getUnitContextLabel(key)
			if isSelected then
				button:SetText("[" .. label .. "]")
			else
				button:SetText(label)
			end
		end
	end

	for i = 1, #SPECIAL_DEBUFF_GROUPS do
		local group = SPECIAL_DEBUFF_GROUPS[i]
		local check = frame.SpecialChecks and frame.SpecialChecks[group.key]
		if check then
			check:SetChecked(bucket.specialDebuffs and bucket.specialDebuffs[group.key] == true)
			updateCheckEnabledVisual(check, cfg.enabled == true)
		end
	end

	if frame.FamilyRows then
		for i = 1, #frame.FamilyRows do
			local row = frame.FamilyRows[i]
			if row and row._familyId then
				row:SetChecked(bucket.ignoredFamilies and bucket.ignoredFamilies[row._familyId] == true)
				updateCheckEnabledVisual(row, cfg.enabled == true)
			end
		end
	end
end

function GAI:ToggleEditor(context)
	local frame = buildEditor()
	if not frame then return end
	if frame:IsShown() then
		frame:Hide()
		return
	end
	local resolvedContext = GAI.ResolveContext(context)
	if resolvedContext and UNIT_CONTEXT_LOOKUP[resolvedContext] then frame._selectedContext = resolvedContext end
	frame:Show()
	self:RefreshEditor()
end

function GAI:HideEditor()
	if editorFrame and editorFrame:IsShown() then editorFrame:Hide() end
end

function GAI:GetSpecialDebuffGroups()
	local list = {}
	for i = 1, #SPECIAL_DEBUFF_GROUPS do
		local group = SPECIAL_DEBUFF_GROUPS[i]
		list[#list + 1] = {
			key = group.key,
			label = tr(group.labelKey, group.fallbackLabel),
			spellIds = copyTable(group.spellIds or {}),
		}
	end
	return list
end

function GAI:GetFamilyEntries()
	local entries = getFamilyEntries()
	return copyTable(entries)
end

function GAI:ResetFamilyCache()
	familyEntryList = nil
	familyEntryById = nil
	if editorFrame then rebuildFamilyRows(editorFrame) end
end
