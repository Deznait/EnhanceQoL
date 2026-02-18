local addonName, addon = ...

addon.variables.NewVersionTableEQOL = {
	-- UI -> Map Navigation (Expandable) -> Minimap Button Bin -> Minimap toggle -> Click toggles flyout
	["EQOL_UI"] = true,
	["EQOL_GENERAL"] = true,
	["EQOL_MapNavigation"] = true,
	["EQOL_minimapButtonBinIconClickToggle"] = true,

	-- Gear & Upgrades -> Item level styling + outside positioning
	["EQOL_GearUpgrades"] = true,
	["EQOL_charIlvlPosition"] = true,
	["EQOL_bagIlvlPosition"] = true,
	["EQOL_ilvlUseItemQualityColor"] = true,
	["EQOL_ilvlTextColor"] = true,
	["EQOL_ilvlFontFace"] = true,
	["EQOL_ilvlFontSize"] = true,
	["EQOL_ilvlFontOutline"] = true,

	-- UI -> Castbars & Cooldowns
	["EQOL_CastbarsAndCooldowns"] = true,
	["EQOL_useCustomPlayerCastbar"] = true,
}
