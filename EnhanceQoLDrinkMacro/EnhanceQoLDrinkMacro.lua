local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
local drinkMacroName = "EnhanceQoLDrinkMacro"

local UnitAffectingCombat = UnitAffectingCombat
local InCombatLockdown = InCombatLockdown
local UnitPowerMax = UnitPowerMax
local UnitLevel = UnitLevel
local GetMacroInfo = GetMacroInfo
local EditMacro = EditMacro
local CreateMacro = CreateMacro

-- Recuperate info is shared via addon.Recuperate (Init.lua)

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_DrinkMacro")
local LSM = LibStub("LibSharedMedia-3.0")

local function createMacroIfMissing()
	-- Respect enable toggle and guard against protected calls while in combat lockdown
	if not addon.db.drinkMacroEnabled then return end
	if InCombatLockdown and InCombatLockdown() then return end
	if GetMacroInfo(drinkMacroName) == nil then CreateMacro(drinkMacroName, "INV_Misc_QuestionMark") end
end

-- Find first available mana potion from user-defined list (preserves user order)
local function findBestManaPotion()
	if not addon.db or not addon.db.useManaPotionInCombat then return nil end
	local list = (addon.Drinks and addon.Drinks.manaPotions) or {}
	local playerLevel = UnitLevel("player")
	for i = 1, #list do
		local e = list[i]
		if e and e.id and (e.requiredLevel or 1) <= playerLevel then
			if (C_Item.GetItemCount(e.id, false, false) or 0) > 0 then return "item:" .. e.id end
		end
	end
	return nil
end

local function buildMacroString(drinkItem, manaPotionItem)
	local resetType = "combat"
	local recuperateString = ""

	if addon.db.allowRecuperate and addon.Recuperate and addon.Recuperate.name and addon.Recuperate.known then recuperateString = "\n/cast " .. addon.Recuperate.name end

	local parts = { "#showtooltip" }

	-- Use mana potion during combat, if enabled and found
	if manaPotionItem then table.insert(parts, string.format("/use [combat] %s", manaPotionItem)) end

	if drinkItem == nil then
		if recuperateString ~= "" then table.insert(parts, recuperateString) end
		return table.concat(parts, "\n")
	else
		-- Keep legacy behavior: castsequence for drinks, optional recuperate
		table.insert(parts, string.format("/castsequence reset=%s %s", resetType, drinkItem))
		if recuperateString ~= "" then table.insert(parts, recuperateString) end
		return table.concat(parts, "\n")
	end
end

local function unitHasMana()
	local maxMana = UnitPowerMax("player", Enum.PowerType.Mana)
	return maxMana > 0
end

local lastItemPlaced
local lastManaPotionPlaced
local lastAllowRecuperate
local lastUseRecuperate
local function addDrinks()
	-- Determine best available drink (may be nil) and optional mana potion for combat
	local foundItem = nil
	for _, value in ipairs(addon.Drinks.filteredDrinks or {}) do
		if value.getCount() > 0 then
			foundItem = value.getId()
			break
			-- We only need the highest manadrink
		end
	end

	local manaItem = nil
	if addon.db.useManaPotionInCombat and unitHasMana() then manaItem = findBestManaPotion() end

	if foundItem ~= lastItemPlaced or manaItem ~= lastManaPotionPlaced or addon.db.allowRecuperate ~= lastAllowRecuperate or addon.db.allowRecuperate ~= lastUseRecuperate then
		-- Avoid protected EditMacro during combat lockdown
		if InCombatLockdown and InCombatLockdown() then return end
		EditMacro(drinkMacroName, drinkMacroName, nil, buildMacroString(foundItem, manaItem))
		lastItemPlaced = foundItem
		lastManaPotionPlaced = manaItem
		lastAllowRecuperate = addon.db.allowRecuperate
		lastUseRecuperate = addon.db.allowRecuperate
	end
end

function addon.functions.updateAvailableDrinks(ignoreCombat)
	if not addon.db.drinkMacroEnabled then return end
	if UnitAffectingCombat("player") and ignoreCombat == false then return end
	if unitHasMana() == false and not addon.db.allowRecuperate then return end
	createMacroIfMissing()
	addDrinks()
end

local initialValue = 50
if addon.db["minManaFoodValue"] then
	initialValue = addon.db["minManaFoodValue"]
else
	addon.db["minManaFoodValue"] = initialValue
end

-- TODO combine allowRecuoerate with useRecuperateWithDrinks --> User don't need to "allow" it doubled
-- TODO automatically ignore Gems for earthen, there don't need to be a setting for that, just make a small information, that gems will be ignored automatically
-- TODO always ignore buff food, just "disable" this setting for now, when any person says he needs it, we will be enabling it again, but for now less clutter
addon.functions.InitDBValue("preferMageFood", true)
addon.functions.InitDBValue("drinkMacroEnabled", false)
addon.functions.InitDBValue("allowRecuperate", true)
addon.functions.InitDBValue("useManaPotionInCombat", false)
addon.functions.updateAllowedDrinks()

local frameLoad = CreateFrame("Frame")
-- Registriere das Event
frameLoad:RegisterEvent("PLAYER_LOGIN")
frameLoad:RegisterEvent("PLAYER_REGEN_ENABLED")
frameLoad:RegisterEvent("PLAYER_LEVEL_UP")
frameLoad:RegisterEvent("BAG_UPDATE_DELAYED")
frameLoad:RegisterEvent("SPELLS_CHANGED")
frameLoad:RegisterEvent("PLAYER_TALENT_UPDATE")
-- Funktion zum Umgang mit Events
local pendingUpdate = false
local function eventHandler(self, event, arg1, arg2, arg3, arg4)
	if event == "BAG_UPDATE_DELAYED" then
		if not pendingUpdate then
			pendingUpdate = true
			C_Timer.After(0.05, function()
				addon.functions.updateAvailableDrinks(false)
				pendingUpdate = false
			end)
		end
	elseif event == "PLAYER_LOGIN" then
		if addon.Recuperate and addon.Recuperate.Update then addon.Recuperate.Update() end
		-- on login always load the macro
		addon.functions.updateAllowedDrinks()
		addon.functions.updateAvailableDrinks(false)
	elseif event == "PLAYER_REGEN_ENABLED" then
		-- PLAYER_REGEN_ENABLED always load, because we don't know if something changed in Combat
		addon.functions.updateAvailableDrinks(true)
	elseif event == "PLAYER_LEVEL_UP" and UnitAffectingCombat("player") == false then
		-- on level up, reload the complete list of allowed drinks
		addon.functions.updateAllowedDrinks()
		addon.functions.updateAvailableDrinks(true)
	elseif event == "SPELLS_CHANGED" or event == "PLAYER_TALENT_UPDATE" then
		if addon.Recuperate and addon.Recuperate.Update then addon.Recuperate.Update() end
		addon.functions.updateAvailableDrinks(false)
	end
end
-- Setze den Event-Handler
frameLoad:SetScript("OnEvent", eventHandler)

-- Place Drink Macro under Combat & Dungeons
addon.functions.addToTree("combat", { value = "drink", text = MACROS })
addon.functions.addToTree("combat\001drink", { value = "drinks", text = L["Drinks & Food"] or "Drinks & Food" })

-- Add child entry for Health Macro under Drink Macro
addon.functions.addToTree("combat\001drink", {
	value = "health",
	text = L["Health Macro"],
})
addon.variables.statusTable.groups["drink"] = true

local function addDrinkFrame(container)
	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "Flow")
	scroll:AddChild(wrapper)

	local function doLayout()
		if scroll and scroll.DoLayout then scroll:DoLayout() end
	end
	wrapper:PauseLayout()
	local groups = {}
	local function ensureGroup(key, title)
		local g, known
		if groups[key] then
			g = groups[key]
			g:PauseLayout()
			g:ReleaseChildren()
			known = true
		else
			g = addon.functions.createContainer("InlineGroup", "List")
			if title and title ~= "" then g:SetTitle(title) end
			wrapper:AddChild(g)
			groups[key] = g
		end
		return g, known
	end

	local function buildCore()
		local g, known = ensureGroup("core", L["Drink Macro"]) -- title

		-- Always put the enable toggle first
		local cbEnable = addon.functions.createCheckboxAce(L["Enable Drink Macro"], addon.db.drinkMacroEnabled, function(_, _, v)
			addon.db.drinkMacroEnabled = v
			-- Build lists and macro content immediately to avoid empty macro body
			addon.functions.updateAllowedDrinks()
			addon.functions.updateAvailableDrinks(false)
			buildCore()
		end)
		g:AddChild(cbEnable)

		-- Child group for core settings (only visible if enabled)
		if addon.db.drinkMacroEnabled then
			local sub = addon.functions.createContainer("InlineGroup", "List")
			g:AddChild(sub)

			local cbPreferMage = addon.functions.createCheckboxAce(L["Prefer mage food"], addon.db.preferMageFood, function(_, _, v)
				addon.db.preferMageFood = v
				addon.functions.updateAllowedDrinks()
				addon.functions.updateAvailableDrinks(false)
			end)
			sub:AddChild(cbPreferMage)

			local cbRecup = addon.functions.createCheckboxAce(L["allowRecuperate"], addon.db.allowRecuperate, function(_, _, v)
				addon.db.allowRecuperate = v
				addon.functions.updateAllowedDrinks()
				addon.functions.updateAvailableDrinks(false)
			end, L["allowRecuperateDesc"])
			sub:AddChild(cbRecup)

			local cbUseMana = addon.functions.createCheckboxAce(L["useManaPotionInCombat"], addon.db.useManaPotionInCombat, function(_, _, v)
				addon.db.useManaPotionInCombat = v
				addon.functions.updateAvailableDrinks(false)
			end, L["useManaPotionInCombatDesc"])
			sub:AddChild(cbUseMana)

			local sliderManaMinimum = addon.functions.createSliderAce(
				L["Minimum mana restore for food"] .. ": " .. addon.db.minManaFoodValue .. "%",
				addon.db.minManaFoodValue,
				0,
				100,
				1,
				function(self, _, v)
					addon.db.minManaFoodValue = v
					addon.functions.updateAllowedDrinks()
					addon.functions.updateAvailableDrinks(false)
					self:SetLabel(L["Minimum mana restore for food"] .. ": " .. v .. "%")
				end
			)
			sub:AddChild(sliderManaMinimum)
		end

		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	local function buildReminder()
		local g, known = ensureGroup("reminder", L["MageFoodReminderHeadline"] or "Mage food reminder for Healer")

		local cbReminder = addon.functions.createCheckboxAce(L["mageFoodReminder"], addon.db.mageFoodReminder, function(_, _, v)
			addon.db.mageFoodReminder = v
			addon.Drinks.functions.updateRole()
			buildReminder()
		end, L["mageFoodReminderDesc2"])
		g:AddChild(cbReminder)

		if addon.db.mageFoodReminder then
			local cbSound = addon.functions.createCheckboxAce(L["mageFoodReminderSound"], addon.db.mageFoodReminderSound, function(_, _, v)
				addon.db.mageFoodReminderSound = v
				addon.Drinks.functions.updateRole()
				buildReminder()
			end)
			g:AddChild(cbSound)

			if addon.db.mageFoodReminderSound then
				local cbCustom = addon.functions.createCheckboxAce(L["mageFoodReminderUseCustomSound"], addon.db.mageFoodReminderUseCustomSound, function(_, _, v)
					addon.db.mageFoodReminderUseCustomSound = v
					buildReminder()
				end)
				g:AddChild(cbCustom)

				if addon.db.mageFoodReminderUseCustomSound then
					local soundList = {}
					if addon.ChatIM and addon.ChatIM.BuildSoundTable and not addon.ChatIM.availableSounds then addon.ChatIM:BuildSoundTable() end
					local soundTable = (addon.ChatIM and addon.ChatIM.availableSounds) or LSM:HashTable("sound")
					for name in pairs(soundTable or {}) do
						soundList[name] = name
					end
					local list, order = addon.functions.prepareListForDropdown(soundList)

					local dropJoin = addon.functions.createDropdownAce(L["mageFoodReminderJoinSound"], list, order, function(self, _, val)
						addon.db.mageFoodReminderJoinSoundFile = val
						self:SetValue(val)
						local f = soundTable and soundTable[val]
						if f then PlaySoundFile(f, "Master") end
					end)
					dropJoin:SetValue(addon.db.mageFoodReminderJoinSoundFile)
					g:AddChild(dropJoin)

					local dropLeave = addon.functions.createDropdownAce(L["mageFoodReminderLeaveSound"], list, order, function(self, _, val)
						addon.db.mageFoodReminderLeaveSoundFile = val
						self:SetValue(val)
						local f = soundTable and soundTable[val]
						if f then PlaySoundFile(f, "Master") end
					end)
					dropLeave:SetValue(addon.db.mageFoodReminderLeaveSoundFile)
					g:AddChild(dropLeave)
				end
			end

			local sliderReminderSize = addon.functions.createSliderAce(
				L["mageFoodReminderSize"] .. ": " .. addon.db.mageFoodReminderScale,
				addon.db.mageFoodReminderScale,
				0.5,
				2,
				0.05,
				function(self, _, v)
					addon.db.mageFoodReminderScale = v
					addon.Drinks.functions.updateRole()
					self:SetLabel(L["mageFoodReminderSize"] .. ": " .. v)
				end
			)
			g:AddChild(sliderReminderSize)

			local resetReminderPos = addon.functions.createButtonAce(L["mageFoodReminderReset"], 150, function()
				addon.db.mageFoodReminderPos = { point = "TOP", x = 0, y = -100 }
				addon.Drinks.functions.updateRole()
			end)
			g:AddChild(resetReminderPos)
		end

		if known then
			g:ResumeLayout()
			doLayout()
		end
	end

	buildCore()
	buildReminder()
	wrapper:ResumeLayout()
	doLayout()
end

-- TODO put all the options from HealthMacro into the same menu of DrinkMacro and remove the subtree node "health"
function addon.Drinks.functions.treeCallback(container, group)
	container:ReleaseChildren() -- Entfernt vorherige Inhalte
	-- Prüfen, welche Gruppe ausgewählt wurde
	if group == "drink" or group == "drink\001drinks" then
		addDrinkFrame(container)
	elseif group == "drink\001health" then
		if addon.Health and addon.Health.functions and addon.Health.functions.addHealthFrame then addon.Health.functions.addHealthFrame(container) end
	end
end
