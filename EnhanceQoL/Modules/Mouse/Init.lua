local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.Mouse = addon.Mouse or {}
addon.Mouse.functions = addon.Mouse.functions or {}
addon.Mouse.variables = addon.Mouse.variables or {}
addon.LMouse = addon.LMouse or {} -- Locales for mouse

function addon.Mouse.functions.InitDB()
	if not addon.db or not addon.functions or not addon.functions.InitDBValue then return end
	local init = addon.functions.InitDBValue
	init("mouseRingEnabled", false)
	init("mouseTrailEnabled", false)
	init("mouseTrailDensity", 1)
	init("mouseRingSize", 70)
	init("mouseRingHideDot", false)
	-- New options
	init("mouseRingOnlyInCombat", false)
	init("mouseRingOnlyOnRightClick", false)
	init("mouseTrailOnlyInCombat", false)
	init("mouseRingUseClassColor", false)
	init("mouseTrailUseClassColor", false)
end
