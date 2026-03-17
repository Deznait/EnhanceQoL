local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
local InCombatLockdown = InCombatLockdown
local GetMacroInfo = GetMacroInfo
local GetNumMacros = GetNumMacros
local CreateMacro = CreateMacro
local EditMacro = EditMacro
local print = print
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.Drinks = addon.Drinks or {}
addon.Drinks.functions = addon.Drinks.functions or {}
addon.Drinks.filteredDrinks = addon.Drinks.filteredDrinks or {} -- Used for the filtered List later
addon.LDrinkMacro = addon.LDrinkMacro or {} -- Locales for drink macro

-- Flask macro module scaffolding
addon.Flasks = addon.Flasks or {}
addon.Flasks.functions = addon.Flasks.functions or {}
addon.Flasks.filteredFlasks = addon.Flasks.filteredFlasks or {}

-- Buff food macro module scaffolding
addon.BuffFoods = addon.BuffFoods or {}
addon.BuffFoods.functions = addon.BuffFoods.functions or {}
addon.BuffFoods.filteredBuffFoods = addon.BuffFoods.filteredBuffFoods or {}

-- Health macro module scaffolding
addon.Health = addon.Health or {}
addon.Health.functions = addon.Health.functions or {}
addon.Health.filteredHealth = addon.Health.filteredHealth or {}

-- Shared Recuperate spell info (used by Drink and Health macros)
addon.Recuperate = addon.Recuperate or {
	id = 1231411, -- Recuperate spell id
	name = nil,
	known = false,
}
addon.macroWarnings = addon.macroWarnings or {}

function addon.Recuperate.Update()
	local spellInfo = C_Spell.GetSpellInfo(addon.Recuperate.id)
	addon.Recuperate.name = spellInfo and spellInfo.name or nil
	addon.Recuperate.known = addon.Recuperate.name and C_SpellBook.IsSpellInSpellBook(addon.Recuperate.id) or false
end

function addon.functions.newItem(id, name, isSpell)
	local self = {}

	self.id = id
	self.name = name
	self.isSpell = isSpell

	local function setName()
		local itemInfoName = C_Item.GetItemInfo(self.id)
		if itemInfoName ~= nil then self.name = itemInfoName end
	end

	function self.getId()
		if self.isSpell then return C_Spell.GetSpellName(self.id) end
		return "item:" .. self.id
	end

	function self.getName() return self.name end

	function self.getCount()
		if self.isSpell then return 1 end
		return C_Item.GetItemCount(self.id, false, false)
	end

	return self
end

function addon.functions.WarnMacroLimitReachedOnce(key, message)
	if not key or not message then return end
	if addon.macroWarnings[key] then return end
	addon.macroWarnings[key] = true
	print(message)
end

function addon.functions.EnsureGlobalMacro(name, icon, body, warningKey, warningMessage)
	if not name then return false end
	if GetMacroInfo(name) ~= nil then return true end
	if InCombatLockdown and InCombatLockdown() then return false end

	local globalMacros = 0
	if GetNumMacros then globalMacros = select(1, GetNumMacros()) or 0 end
	local globalLimit = _G.MAX_ACCOUNT_MACROS or 120
	if globalMacros >= globalLimit then
		addon.functions.WarnMacroLimitReachedOnce(warningKey or name, warningMessage)
		return false
	end

	CreateMacro(name, icon or "INV_Misc_QuestionMark")
	if body and GetMacroInfo(name) ~= nil and not (InCombatLockdown and InCombatLockdown()) then EditMacro(name, name, nil, body) end
	return GetMacroInfo(name) ~= nil
end
