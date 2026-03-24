local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
local LMP = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_MythicPlus")
local issecretvalue = _G.issecretvalue

---- REGION Functions
local timeoutReleaseDifficultyLookup = {}

local cChar = addon.SettingsLayout.rootGAMEPLAY
addon.SettingsLayout.characterInspectCategory = cChar
local data

local COMBAT_LOG_DIFFICULTY_DB_KEYS = {
	dungeon = "combatLogDungeonDifficulties",
	raid = "combatLogRaidDifficulties",
}
local COMBAT_LOG_TOGGLE_DB_KEYS = {
	pvp = "combatLogPvp",
	scenario = "combatLogScenario",
	delve = "combatLogDelve",
}
local COMBAT_LOG_DELAY_SECONDS = 30
local combatLogInstanceMap = {
	party = "dungeon",
	raid = "raid",
	pvp = "pvp",
	arena = "pvp",
	scenario = "scenario",
	delve = "delve",
}
local LEGACY_NAMEPLATE_AURA_CLICKTHROUGH_DB_KEY = "experimentalNameplateAuraClickthrough"
local NAMEPLATE_AURA_CLICKTHROUGH_DB_KEY = "nameplateAuraClickthrough"
local NAMEPLATE_MOB_COLORS_DB_KEY = "nameplateMobColors"
local NAMEPLATE_MOB_COLOR_BOSS_DB_KEY = "nameplateMobColorBoss"
local NAMEPLATE_MOB_COLOR_MINIBOSS_DB_KEY = "nameplateMobColorMiniboss"
local NAMEPLATE_MOB_COLOR_CASTER_DB_KEY = "nameplateMobColorCaster"
local NAMEPLATE_MOB_COLOR_MELEE_DB_KEY = "nameplateMobColorMelee"
local NAMEPLATE_MOB_COLOR_TRIVIAL_DB_KEY = "nameplateMobColorTrivial"
local nameplateAuraClickthroughFrame
local nameplateAuraClickthroughHookedBuffPools = setmetatable({}, { __mode = "k" })
local nameplateAuraClickthroughHookedAuraFrames = setmetatable({}, { __mode = "k" })
local nameplateAuraClickthroughActive = false
local nameplateMobColorFrame
local nameplateMobColorHooksInstalled = false
local nameplateMobColorsActive = false
local nameplateMobColorState = {
	isActive = false,
	lastLFGInstanceID = nil,
	referenceLevel = nil,
	lieutenantLevel = nil,
}
local NAMEPLATE_MOB_COLOR_DEFAULTS = {
	[NAMEPLATE_MOB_COLOR_BOSS_DB_KEY] = { r = 188 / 255, g = 28 / 255, b = 0 / 255, a = 1 },
	[NAMEPLATE_MOB_COLOR_MINIBOSS_DB_KEY] = { r = 144 / 255, g = 0 / 255, b = 188 / 255, a = 1 },
	[NAMEPLATE_MOB_COLOR_CASTER_DB_KEY] = { r = 0 / 255, g = 116 / 255, b = 188 / 255, a = 1 },
	[NAMEPLATE_MOB_COLOR_MELEE_DB_KEY] = { r = 252 / 255, g = 252 / 255, b = 252 / 255, a = 1 },
	[NAMEPLATE_MOB_COLOR_TRIVIAL_DB_KEY] = { r = 178 / 255, g = 142 / 255, b = 85 / 255, a = 1 },
}
addon.constants = addon.constants or {}
addon.constants.DEFAULT_NAMEPLATE_FEATURE_KEYS = {
	auraClickthrough = NAMEPLATE_AURA_CLICKTHROUGH_DB_KEY,
	mobColors = NAMEPLATE_MOB_COLORS_DB_KEY,
	mobColorBoss = NAMEPLATE_MOB_COLOR_BOSS_DB_KEY,
	mobColorMiniboss = NAMEPLATE_MOB_COLOR_MINIBOSS_DB_KEY,
	mobColorCaster = NAMEPLATE_MOB_COLOR_CASTER_DB_KEY,
	mobColorMelee = NAMEPLATE_MOB_COLOR_MELEE_DB_KEY,
	mobColorTrivial = NAMEPLATE_MOB_COLOR_TRIVIAL_DB_KEY,
}
local DIFFICULTY_IDS = (_G.DifficultyUtil and _G.DifficultyUtil.ID) or {}
local COMBAT_LOG_DIFFICULTY_GROUPS = {
	dungeon = {
		{ key = "normal", text = PLAYER_DIFFICULTY1, difficulties = { DIFFICULTY_IDS.DungeonNormal or 1, 150, 216 } },
		{ key = "heroic", text = PLAYER_DIFFICULTY2, difficulties = { DIFFICULTY_IDS.DungeonHeroic or 2 } },
		{ key = "mythic", text = PLAYER_DIFFICULTY6, difficulties = { DIFFICULTY_IDS.DungeonMythic or 23 } },
		{ key = "mythicPlus", text = PLAYER_DIFFICULTY_MYTHIC_PLUS, difficulties = { DIFFICULTY_IDS.DungeonChallenge or 8 } },
		{ key = "timewalking", text = PLAYER_DIFFICULTY_TIMEWALKER, difficulties = { DIFFICULTY_IDS.DungeonTimewalker or 24 } },
	},
	raid = {
		{ key = "lfr", text = PLAYER_DIFFICULTY3, difficulties = { DIFFICULTY_IDS.RaidLFR or 7, DIFFICULTY_IDS.PrimaryRaidLFR or 17, 151 } },
		{
			key = "normal",
			text = PLAYER_DIFFICULTY1,
			difficulties = {
				DIFFICULTY_IDS.Raid10Normal or 3,
				DIFFICULTY_IDS.Raid25Normal or 4,
				DIFFICULTY_IDS.PrimaryRaidNormal or 14,
				DIFFICULTY_IDS.Raid40 or 9,
				DIFFICULTY_IDS.RaidStory or 220,
			},
		},
		{ key = "heroic", text = PLAYER_DIFFICULTY2, difficulties = { DIFFICULTY_IDS.Raid10Heroic or 5, DIFFICULTY_IDS.Raid25Heroic or 6, DIFFICULTY_IDS.PrimaryRaidHeroic or 15 } },
		{ key = "mythic", text = PLAYER_DIFFICULTY6, difficulties = { DIFFICULTY_IDS.PrimaryRaidMythic or 16 } },
		{ key = "timewalking", text = PLAYER_DIFFICULTY_TIMEWALKER, difficulties = { DIFFICULTY_IDS.RaidTimewalker or 33 } },
	},
}

local function getCombatLogCategory(instanceType) return combatLogInstanceMap[instanceType] end

local function getCombatLogSelectionTable(category)
	if not addon.db then return nil end
	local key = COMBAT_LOG_DIFFICULTY_DB_KEYS[category]
	if not key then return nil end
	local selection = addon.db[key]
	if type(selection) ~= "table" then
		selection = {}
		addon.db[key] = selection
	end
	return selection
end

local function buildCombatLogDifficultyData()
	addon.variables = addon.variables or {}
	if addon.variables.combatLogDifficultyGroups and addon.variables.combatLogDifficultyLookup then return addon.variables.combatLogDifficultyGroups, addon.variables.combatLogDifficultyLookup end

	local groups = {}
	local lookup = {}
	for category, entries in pairs(COMBAT_LOG_DIFFICULTY_GROUPS) do
		groups[category] = entries
		lookup[category] = {}
		for _, entry in ipairs(entries) do
			for _, difficultyID in ipairs(entry.difficulties or {}) do
				lookup[category][difficultyID] = entry.key
			end
		end
	end

	addon.variables.combatLogDifficultyGroups = groups
	addon.variables.combatLogDifficultyLookup = lookup
	return groups, lookup
end

local function getCombatLogDifficultyOptions(category)
	local groups = buildCombatLogDifficultyData()
	local options = {}
	for _, entry in ipairs(groups[category] or {}) do
		options[#options + 1] = { value = entry.key, text = entry.text }
	end
	return options
end

local function getCombatLogDifficultyKey(category, difficultyID)
	local _, lookup = buildCombatLogDifficultyData()
	local bucket = lookup[category]
	return bucket and bucket[difficultyID]
end

local function setCombatLogSelection(category, key, enabled)
	local selection = getCombatLogSelectionTable(category)
	if not selection or not key then return end
	selection[key] = enabled and true or false
	if addon.db and addon.db.autoCombatLog then
		if addon.functions.UpdateCombatLogState then addon.functions.UpdateCombatLogState() end
	end
end

local function isCombatLogSelected(category, key)
	local selection = getCombatLogSelectionTable(category)
	return selection and selection[key] == true
end

local function isCombatLogToggleEnabled(category)
	local key = COMBAT_LOG_TOGGLE_DB_KEYS[category]
	if not key or not addon.db then return false end
	return addon.db[key] == true
end

local function getCombatLogDecision(category, difficultyID)
	if COMBAT_LOG_TOGGLE_DB_KEYS[category] then return isCombatLogToggleEnabled(category) end
	local key = getCombatLogDifficultyKey(category, difficultyID)
	if not key then return nil end
	return isCombatLogSelected(category, key)
end

local function printCombatLogMessage(message)
	if not message or message == "" then return end
	local prefix = "|cff33ff99EQOL|r: "
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(prefix .. message)
	else
		print(prefix .. message)
	end
end

local function cancelCombatLogStopTimer()
	if not addon.variables or not addon.variables.combatLogStopTimer then return end
	if addon.variables.combatLogStopTimer.Cancel then addon.variables.combatLogStopTimer:Cancel() end
	addon.variables.combatLogStopTimer = nil
end

local function getCombatLogEnabledState()
	local enabled = C_ChatInfo.IsLoggingCombat()
	return enabled and true or false
end

local function applyCombatLogState(enabled)
	local logger = _G.LoggingCombat
	if not logger then return end
	local target = enabled and true or false
	if target then
		cancelCombatLogStopTimer()
		local current = getCombatLogEnabledState()
		if current then return end
		logger(true)
		printCombatLogMessage(L["combatLogEnabledMsg"] or "Combat logging enabled.")
		return
	end

	if addon.db and addon.db.combatLogDelayedStop and C_Timer and C_Timer.NewTimer then
		local current = getCombatLogEnabledState()
		if not current then return end
		cancelCombatLogStopTimer()
		addon.variables = addon.variables or {}
		addon.variables.combatLogStopTimer = C_Timer.NewTimer(COMBAT_LOG_DELAY_SECONDS, function()
			addon.variables.combatLogStopTimer = nil
			if getCombatLogEnabledState() then
				logger(false)
				printCombatLogMessage(L["combatLogDisabledMsg"] or "Combat logging disabled.")
			end
		end)
		return
	end

	cancelCombatLogStopTimer()
	local current = getCombatLogEnabledState()
	if current == target then return end
	logger(false)
	printCombatLogMessage(L["combatLogDisabledMsg"] or "Combat logging disabled.")
end

local function updateCombatLogState()
	if not addon.db or not addon.db.autoCombatLog then
		if addon.variables and addon.variables.combatLogRestoreState ~= nil then
			applyCombatLogState(addon.variables.combatLogRestoreState)
			addon.variables.combatLogRestoreState = nil
		end
		return
	end

	local _, instanceType, difficultyID = GetInstanceInfo()
	if not instanceType or instanceType == "none" then
		if addon.variables and addon.variables.combatLogRestoreState ~= nil then
			applyCombatLogState(addon.variables.combatLogRestoreState)
			addon.variables.combatLogRestoreState = nil
		end
		return
	end

	local category = getCombatLogCategory(instanceType)
	if not category then return end
	if addon.variables and addon.variables.combatLogRestoreState == nil then addon.variables.combatLogRestoreState = getCombatLogEnabledState() end

	local decision = getCombatLogDecision(category, difficultyID)
	if decision == nil then return end
	applyCombatLogState(decision)
end

addon.functions.UpdateCombatLogState = updateCombatLogState

local function isNameplateAuraClickthroughActive() return nameplateAuraClickthroughActive == true end

local function isSecretValue(value) return issecretvalue and issecretvalue(value) end

local function isNameplateUnitToken(unit)
	if type(unit) ~= "string" or isSecretValue(unit) then return false end
	return unit:match("^nameplate%d+$") ~= nil
end

local function isNeutralUnit(unit)
	if not isNameplateUnitToken(unit) then return false end

	if type(UnitSelectionType) == "function" then
		local selectionType = UnitSelectionType(unit)
		if not isSecretValue(selectionType) then return selectionType == 2 end
	end

	local reaction = UnitReaction(unit, "player")
	if isSecretValue(reaction) then return false end
	return reaction == 4
end

local function isNameplateMobColorsActive() return nameplateMobColorsActive == true end

local function updateNameplateMobColorContext(forceRefresh)
	local isFeatureEnabled = isNameplateMobColorsActive()
	local _, instanceType, _, _, _, _, _, _, _, lfgDungeonID = GetInstanceInfo()
	if isSecretValue(instanceType) then instanceType = nil end
	if isSecretValue(lfgDungeonID) then lfgDungeonID = nil end

	if not isFeatureEnabled then
		nameplateMobColorState.isActive = false
		nameplateMobColorState.lastLFGInstanceID = lfgDungeonID
		nameplateMobColorState.referenceLevel = nil
		nameplateMobColorState.lieutenantLevel = nil
		return
	end

	if not forceRefresh and nameplateMobColorState.isActive == true and nameplateMobColorState.lastLFGInstanceID == lfgDungeonID and nameplateMobColorState.referenceLevel ~= nil then return end

	nameplateMobColorState.isActive = true
	nameplateMobColorState.lastLFGInstanceID = lfgDungeonID
	nameplateMobColorState.lieutenantLevel = nil

	local referenceLevel
	if lfgDungeonID and instanceType == "party" and type(_G.GetMaximumExpansionLevel) == "function" and type(_G.GetMaxLevelForExpansionLevel) == "function" then
		local maximumExpansionLevel = _G.GetMaximumExpansionLevel()
		if not isSecretValue(maximumExpansionLevel) then
			referenceLevel = _G.GetMaxLevelForExpansionLevel(maximumExpansionLevel)
			if isSecretValue(referenceLevel) then referenceLevel = nil end
		end
	end

	if type(referenceLevel) ~= "number" then
		referenceLevel = UnitEffectiveLevel and UnitEffectiveLevel("player")
		if isSecretValue(referenceLevel) then referenceLevel = nil end
	end
	if type(referenceLevel) ~= "number" and type(UnitLevel) == "function" then
		referenceLevel = UnitLevel("player")
		if isSecretValue(referenceLevel) then referenceLevel = nil end
	end

	nameplateMobColorState.referenceLevel = type(referenceLevel) == "number" and referenceLevel or nil
end

local function getNameplateHealthBar(unitFrame)
	if not unitFrame or isSecretValue(unitFrame) then return nil end

	local healthBar = unitFrame.healthBar
	if not healthBar and unitFrame.HealthBarsContainer and not isSecretValue(unitFrame.HealthBarsContainer) then healthBar = unitFrame.HealthBarsContainer.healthBar end
	if not healthBar and unitFrame.HealthBar then healthBar = unitFrame.HealthBar end
	if isSecretValue(healthBar) then return nil end
	if healthBar and healthBar.IsForbidden and healthBar:IsForbidden() then return nil end
	return healthBar
end

local function getNameplateMobColor(dbKey)
	local color = addon.db and addon.db[dbKey]
	if type(color) ~= "table" then color = NAMEPLATE_MOB_COLOR_DEFAULTS[dbKey] end
	if type(color) ~= "table" then return nil end
	return color
end

local function computeNameplateMobColor(unit)
	updateNameplateMobColorContext()
	if not nameplateMobColorState.isActive then return nil end
	if not isNameplateUnitToken(unit) then return nil end
	if isNeutralUnit(unit) then return nil end

	local canAttack = UnitCanAttack("player", unit)
	if isSecretValue(canAttack) or not canAttack then return nil end

	local classification = UnitClassification and UnitClassification(unit)
	if isSecretValue(classification) then classification = nil end
	if classification == "elite" then
		local mobLevel = UnitEffectiveLevel and UnitEffectiveLevel(unit)
		if isSecretValue(mobLevel) then mobLevel = nil end
		if type(mobLevel) ~= "number" and type(UnitLevel) == "function" then
			mobLevel = UnitLevel(unit)
			if isSecretValue(mobLevel) then mobLevel = nil end
		end

		local isLieutenant = type(_G.UnitIsLieutenant) == "function" and _G.UnitIsLieutenant(unit) or false
		if isSecretValue(isLieutenant) then isLieutenant = false end

		local referenceLevel = nameplateMobColorState.referenceLevel
		local lieutenantLevel = nameplateMobColorState.lieutenantLevel
		if type(mobLevel) == "number" and (mobLevel == (referenceLevel and referenceLevel + 1) or isLieutenant) then
			nameplateMobColorState.lieutenantLevel = mobLevel
			return getNameplateMobColor(NAMEPLATE_MOB_COLOR_MINIBOSS_DB_KEY)
		elseif mobLevel == -1 or (type(mobLevel) == "number" and ((referenceLevel and mobLevel == (referenceLevel + 2)) or (lieutenantLevel and mobLevel == (lieutenantLevel + 1)))) then
			return getNameplateMobColor(NAMEPLATE_MOB_COLOR_BOSS_DB_KEY)
		end

		local classToken = UnitClassBase and UnitClassBase(unit)
		if isSecretValue(classToken) then classToken = nil end
		if classToken == "PALADIN" then
			return getNameplateMobColor(NAMEPLATE_MOB_COLOR_CASTER_DB_KEY)
		else
			return getNameplateMobColor(NAMEPLATE_MOB_COLOR_MELEE_DB_KEY)
		end
	elseif classification == "normal" or classification == "trivial" or classification == "minus" then
		return getNameplateMobColor(NAMEPLATE_MOB_COLOR_TRIVIAL_DB_KEY)
	end

	return nil
end

local function applyNameplateMobColor(unitFrame)
	if not unitFrame or isSecretValue(unitFrame) then return end

	local unit = unitFrame.unit
	if not isNameplateUnitToken(unit) then return end

	local color = computeNameplateMobColor(unit)
	if not color then return end

	local healthBar = getNameplateHealthBar(unitFrame)
	if not healthBar then return end

	local currentR, currentG, currentB = healthBar:GetStatusBarColor()
	local targetR = isSecretValue(color.r) and nil or color.r
	local targetG = isSecretValue(color.g) and nil or color.g
	local targetB = isSecretValue(color.b) and nil or color.b
	if type(targetR) ~= "number" or type(targetG) ~= "number" or type(targetB) ~= "number" then return end
	if currentR == targetR and currentG == targetG and currentB == targetB then return end
	healthBar:SetStatusBarColor(targetR, targetG, targetB)
end

local function refreshNameplateMobColorUnitFrame(unitFrame)
	if not unitFrame or isSecretValue(unitFrame) then return end
	if not isNameplateUnitToken(unitFrame.unit) then return end

	if type(_G.CompactUnitFrame_UpdateHealthColor) == "function" then
		_G.CompactUnitFrame_UpdateHealthColor(unitFrame)
		return
	end

	applyNameplateMobColor(unitFrame)
end

local function refreshAllNameplateMobColors()
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
	for _, namePlate in pairs(C_NamePlate.GetNamePlates() or {}) do
		local unitFrame = namePlate and namePlate.UnitFrame
		if unitFrame then refreshNameplateMobColorUnitFrame(unitFrame) end
	end
end

local function ensureNameplateMobColorHooks()
	if nameplateMobColorHooksInstalled then return end
	if type(hooksecurefunc) ~= "function" then return end
	local installedAnyHook = false

	if type(_G.CompactUnitFrame_UpdateHealthColor) == "function" then
		hooksecurefunc("CompactUnitFrame_UpdateHealthColor", function(unitFrame) applyNameplateMobColor(unitFrame) end)
		installedAnyHook = true
	end

	if type(_G.CompactUnitFrame_UpdateAll) == "function" then
		hooksecurefunc("CompactUnitFrame_UpdateAll", function(unitFrame) applyNameplateMobColor(unitFrame) end)
		installedAnyHook = true
	end

	nameplateMobColorHooksInstalled = installedAnyHook
end

local function ensureNameplateMobColorWatcher()
	ensureNameplateMobColorHooks()
	if nameplateMobColorFrame then return end

	nameplateMobColorFrame = CreateFrame("Frame")
	nameplateMobColorFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	nameplateMobColorFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	nameplateMobColorFrame:RegisterEvent("PLAYER_LEVEL_UP")
	nameplateMobColorFrame:RegisterEvent("INSTANCE_GROUP_SIZE_CHANGED")
	nameplateMobColorFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	nameplateMobColorFrame:SetScript("OnEvent", function(_, event, unit)
		ensureNameplateMobColorHooks()
		local forceRefresh = event ~= "NAME_PLATE_UNIT_ADDED"
		updateNameplateMobColorContext(forceRefresh)
		if event == "NAME_PLATE_UNIT_ADDED" and unit and C_NamePlate and C_NamePlate.GetNamePlateForUnit then
			local namePlate = C_NamePlate.GetNamePlateForUnit(unit)
			local unitFrame = namePlate and namePlate.UnitFrame
			if unitFrame then refreshNameplateMobColorUnitFrame(unitFrame) end
			return
		end

		refreshAllNameplateMobColors()
	end)
end

local function syncNameplateMobColors()
	if not isNameplateMobColorsActive() then return end
	ensureNameplateMobColorWatcher()
	updateNameplateMobColorContext()
	refreshAllNameplateMobColors()
end

local function safeSetNameplateAuraButtonClicks(button, enabled)
	if not button or type(button.SetMouseClickEnabled) ~= "function" then return false end
	local ok = pcall(button.SetMouseClickEnabled, button, enabled and true or false)
	return ok == true
end

local function applyNameplateAuraClickthroughToBuffPool(pool)
	if not pool or type(pool.EnumerateActive) ~= "function" then return end
	local allowClicks = not isNameplateAuraClickthroughActive()
	for button in pool:EnumerateActive() do
		safeSetNameplateAuraButtonClicks(button, allowClicks)
	end
end

local function applyNameplateAuraClickthroughToAurasFrame(aurasFrame)
	if not aurasFrame then return end

	local allowClicks = not isNameplateAuraClickthroughActive()
	local pool = aurasFrame.auraItemFramePool
	if pool and type(pool.EnumerateActive) == "function" then
		for auraItem in pool:EnumerateActive() do
			safeSetNameplateAuraButtonClicks(auraItem, allowClicks)
		end
	end

	local lossOfControlAura = aurasFrame.LossOfControlFrame and aurasFrame.LossOfControlFrame.AuraItemFrame
	if lossOfControlAura then safeSetNameplateAuraButtonClicks(lossOfControlAura, allowClicks) end
end

local function hookNameplateAuraClickthroughOnBuffFrame(buffFrame)
	if not buffFrame then return end

	local pool = buffFrame.buffPool
	if pool and not nameplateAuraClickthroughHookedBuffPools[pool] and type(pool.resetterFunc) == "function" then
		hooksecurefunc(pool, "resetterFunc", function(_, button)
			local allowClicks = not isNameplateAuraClickthroughActive()
			safeSetNameplateAuraButtonClicks(button, allowClicks)
		end)
		nameplateAuraClickthroughHookedBuffPools[pool] = true
	end

	if not buffFrame._eqolNameplateAuraClickthroughHooked and type(buffFrame.UpdateBuffs) == "function" then
		hooksecurefunc(buffFrame, "UpdateBuffs", function(self) applyNameplateAuraClickthroughToBuffPool(self.buffPool) end)
		buffFrame._eqolNameplateAuraClickthroughHooked = true
	end

	applyNameplateAuraClickthroughToBuffPool(pool)
end

local function hookNameplateAuraClickthroughOnAurasFrame(aurasFrame)
	if not aurasFrame or nameplateAuraClickthroughHookedAuraFrames[aurasFrame] then return end

	if type(aurasFrame.RefreshAuras) == "function" then hooksecurefunc(aurasFrame, "RefreshAuras", function(self) applyNameplateAuraClickthroughToAurasFrame(self) end) end

	if type(aurasFrame.RefreshLossOfControl) == "function" then hooksecurefunc(aurasFrame, "RefreshLossOfControl", function(self) applyNameplateAuraClickthroughToAurasFrame(self) end) end

	nameplateAuraClickthroughHookedAuraFrames[aurasFrame] = true
	applyNameplateAuraClickthroughToAurasFrame(aurasFrame)
end

local function hookNameplateAuraClickthroughOnUnitFrame(unitFrame)
	if not unitFrame then return end
	hookNameplateAuraClickthroughOnBuffFrame(unitFrame.BuffFrame)
	hookNameplateAuraClickthroughOnAurasFrame(unitFrame.AurasFrame)
end

local function applyNameplateAuraClickthroughToNameplate(namePlate)
	if not namePlate or not namePlate.UnitFrame then return end
	hookNameplateAuraClickthroughOnUnitFrame(namePlate.UnitFrame)
end

local function applyNameplateAuraClickthroughToAllNameplates()
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
	for _, namePlate in pairs(C_NamePlate.GetNamePlates() or {}) do
		applyNameplateAuraClickthroughToNameplate(namePlate)
	end
end

local function ensureNameplateAuraClickthroughWatcher()
	if nameplateAuraClickthroughFrame then return end

	nameplateAuraClickthroughFrame = CreateFrame("Frame")
	nameplateAuraClickthroughFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	nameplateAuraClickthroughFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	nameplateAuraClickthroughFrame:SetScript("OnEvent", function(_, event, unit)
		if event == "NAME_PLATE_UNIT_ADDED" and unit and C_NamePlate and C_NamePlate.GetNamePlateForUnit then
			local namePlate = C_NamePlate.GetNamePlateForUnit(unit)
			if namePlate then applyNameplateAuraClickthroughToNameplate(namePlate) end
			return
		end

		applyNameplateAuraClickthroughToAllNameplates()
	end)
end

local function syncNameplateAuraClickthrough()
	if not isNameplateAuraClickthroughActive() then return end
	ensureNameplateAuraClickthroughWatcher()
	applyNameplateAuraClickthroughToAllNameplates()
end

local function requestFeatureReload()
	addon.variables = addon.variables or {}
	addon.variables.requireReload = true
	if addon.functions.checkReloadFrame then addon.functions.checkReloadFrame() end
end

function addon.functions.SetDefaultNameplateAuraClickthroughEnabled(value)
	local wasActive = isNameplateAuraClickthroughActive()
	local enabled = value and true or false
	addon.db[NAMEPLATE_AURA_CLICKTHROUGH_DB_KEY] = enabled
	if enabled then
		nameplateAuraClickthroughActive = true
		syncNameplateAuraClickthrough()
	elseif wasActive then
		requestFeatureReload()
	end
end

function addon.functions.SetDefaultNameplateMobColorsEnabled(value)
	local wasActive = isNameplateMobColorsActive()
	local enabled = value and true or false
	addon.db[NAMEPLATE_MOB_COLORS_DB_KEY] = enabled
	if enabled then
		nameplateMobColorsActive = true
		syncNameplateMobColors()
	elseif wasActive then
		requestFeatureReload()
	end
end

function addon.functions.RefreshDefaultNameplateMobColors()
	if isNameplateMobColorsActive() then syncNameplateMobColors() end
end

local function shouldUseTimeoutReleaseForCurrentContext()
	if not addon.db or not addon.db["timeoutRelease"] then return false end

	local selection = addon.db["timeoutReleaseDifficulties"]
	if selection == nil then return true end

	local hasSelection = false
	for key, enabled in pairs(selection) do
		if enabled then
			hasSelection = true
			break
		end
	end
	if not hasSelection then return false end

	local inInstance, instanceType = IsInInstance()
	if not inInstance or instanceType == "none" then return selection["world"] and true or false end

	local difficultyID = select(3, GetInstanceInfo())
	if difficultyID then
		local keys = timeoutReleaseDifficultyLookup[difficultyID]
		if keys then
			for _, key in ipairs(keys) do
				if selection[key] then return true end
			end
		end
	end

	if instanceType == "scenario" then return selection["scenario"] and true or false end
	if instanceType == "pvp" or instanceType == "arena" then return selection["pvp"] and true or false end
	if instanceType == "raid" then return selection["raidNormal"] or selection["raidHeroic"] or selection["raidMythic"] end
	if instanceType == "party" then return selection["dungeonNormal"] or selection["dungeonHeroic"] or selection["dungeonMythic"] or selection["dungeonMythicPlus"] or selection["dungeonFollower"] end

	return false
end

addon.functions.shouldUseTimeoutReleaseForCurrentContext = shouldUseTimeoutReleaseForCurrentContext

local TIMEOUT_RELEASE_UPDATE_INTERVAL = 0.1

local modifierCheckers = {
	SHIFT = function() return IsShiftKeyDown() end,
	CTRL = function() return IsControlKeyDown() end,
	ALT = function() return IsAltKeyDown() end,
}

local modifierDisplayNames = {
	SHIFT = SHIFT_KEY_TEXT,
	CTRL = CTRL_KEY_TEXT,
	ALT = ALT_KEY_TEXT,
}

local DEFAULT_TIMEOUT_RELEASE_HINT = "Hold %s to release"

function addon.functions.getTimeoutReleaseModifierKey()
	local modifierKey = addon.db and addon.db["timeoutReleaseModifier"] or "SHIFT"
	if not modifierCheckers[modifierKey] then modifierKey = "SHIFT" end
	return modifierKey
end

function addon.functions.isTimeoutReleaseModifierDown(modifierKey)
	local checker = modifierCheckers[modifierKey]
	return checker and checker() or false
end

function addon.functions.getTimeoutReleaseModifierDisplayName(modifierKey) return modifierDisplayNames[modifierKey] or modifierKey end

function addon.functions.showTimeoutReleaseHint(popup, modifierDisplayName)
	if not popup then return end
	local label = popup.eqolTimeoutReleaseLabel
	if not label then
		label = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetJustifyH("CENTER")
		label:SetPoint("BOTTOM", popup, "TOP", 0, 8)
		label:SetTextColor(1, 0.82, 0)
		label:SetWordWrap(true)
		popup.eqolTimeoutReleaseLabel = label
	end
	local hintTemplate = rawget(L, "timeoutReleaseHoldHint") or DEFAULT_TIMEOUT_RELEASE_HINT
	label:SetWidth(popup:GetWidth())
	label:SetText(hintTemplate:format(modifierDisplayName))
	label:Show()
end

function addon.functions.hideTimeoutReleaseHint(popup)
	local label = popup and popup.eqolTimeoutReleaseLabel
	if label then label:Hide() end
end

local function toggleGroupApplication(value)
	if addon.functions and addon.functions.isRestrictedContent and addon.functions.isRestrictedContent(true) then return end
	local viewer = _G.LFGListFrame and _G.LFGListFrame.ApplicationViewer
	local cover = viewer and viewer.UnempoweredCover
	if not (cover and cover.Label and cover.Background and cover.Waitdot1 and cover.Waitdot2 and cover.Waitdot3) then return end
	if value then
		-- Hide overlay and text label
		cover.Label:Hide()
		cover.Background:Hide()
		-- Hide the 3 animated texture icons
		cover.Waitdot1:Hide()
		cover.Waitdot2:Hide()
		cover.Waitdot3:Hide()
	else
		-- Hide overlay and text label
		cover.Label:Show()
		cover.Background:Show()
		-- Hide the 3 animated texture icons
		cover.Waitdot1:Show()
		cover.Waitdot2:Show()
		cover.Waitdot3:Show()
	end
end

local lfgPoint, lfgRelativeTo, lfgRelativePoint, lfgXOfs, lfgYOfs

local function toggleLFGFilterPosition()
	if LFGListFrame and LFGListFrame.SearchPanel and LFGListFrame.SearchPanel.FilterButton and LFGListFrame.SearchPanel.FilterButton.ResetButton then
		if addon.db["groupfinderMoveResetButton"] then
			LFGListFrame.SearchPanel.FilterButton.ResetButton:ClearAllPoints()
			LFGListFrame.SearchPanel.FilterButton.ResetButton:SetPoint("TOPLEFT", LFGListFrame.SearchPanel.FilterButton, "TOPLEFT", -7, 13)
		else
			LFGListFrame.SearchPanel.FilterButton.ResetButton:ClearAllPoints()
			LFGListFrame.SearchPanel.FilterButton.ResetButton:SetPoint(lfgPoint, lfgRelativeTo, lfgRelativePoint, lfgXOfs, lfgYOfs)
		end
	end
end

function addon.functions.initDungeonFrame()
	if addon.db and addon.db[NAMEPLATE_AURA_CLICKTHROUGH_DB_KEY] == nil and addon.db[LEGACY_NAMEPLATE_AURA_CLICKTHROUGH_DB_KEY] ~= nil then
		addon.db[NAMEPLATE_AURA_CLICKTHROUGH_DB_KEY] = addon.db[LEGACY_NAMEPLATE_AURA_CLICKTHROUGH_DB_KEY] and true or false
	end

	addon.functions.InitDBValue("autoChooseDelvePower", false)
	addon.functions.InitDBValue("lfgSortByRio", false)
	addon.functions.InitDBValue("groupfinderSkipRoleSelect", false)
	addon.functions.InitDBValue("enableChatIMRaiderIO", false)
	addon.functions.InitDBValue(NAMEPLATE_AURA_CLICKTHROUGH_DB_KEY, false)
	addon.functions.InitDBValue(NAMEPLATE_MOB_COLORS_DB_KEY, false)
	addon.functions.InitDBValue(NAMEPLATE_MOB_COLOR_BOSS_DB_KEY, NAMEPLATE_MOB_COLOR_DEFAULTS[NAMEPLATE_MOB_COLOR_BOSS_DB_KEY])
	addon.functions.InitDBValue(NAMEPLATE_MOB_COLOR_MINIBOSS_DB_KEY, NAMEPLATE_MOB_COLOR_DEFAULTS[NAMEPLATE_MOB_COLOR_MINIBOSS_DB_KEY])
	addon.functions.InitDBValue(NAMEPLATE_MOB_COLOR_CASTER_DB_KEY, NAMEPLATE_MOB_COLOR_DEFAULTS[NAMEPLATE_MOB_COLOR_CASTER_DB_KEY])
	addon.functions.InitDBValue(NAMEPLATE_MOB_COLOR_MELEE_DB_KEY, NAMEPLATE_MOB_COLOR_DEFAULTS[NAMEPLATE_MOB_COLOR_MELEE_DB_KEY])
	addon.functions.InitDBValue(NAMEPLATE_MOB_COLOR_TRIVIAL_DB_KEY, NAMEPLATE_MOB_COLOR_DEFAULTS[NAMEPLATE_MOB_COLOR_TRIVIAL_DB_KEY])
	addon.functions.InitDBValue("timeoutReleaseDifficulties", {})
	addon.functions.InitDBValue("autoCombatLog", false)
	addon.functions.InitDBValue("combatLogDungeonDifficulties", {})
	addon.functions.InitDBValue("combatLogRaidDifficulties", {})
	addon.functions.InitDBValue("combatLogPvp", false)
	addon.functions.InitDBValue("combatLogScenario", false)
	addon.functions.InitDBValue("combatLogDelve", false)
	addon.functions.InitDBValue("combatLogDelayedStop", false)

	nameplateAuraClickthroughActive = addon.db and addon.db[NAMEPLATE_AURA_CLICKTHROUGH_DB_KEY] == true
	nameplateMobColorsActive = addon.db and addon.db[NAMEPLATE_MOB_COLORS_DB_KEY] == true
	if nameplateAuraClickthroughActive then syncNameplateAuraClickthrough() end
	if nameplateMobColorsActive then syncNameplateMobColors() end

	local combatLogSection = addon.functions.SettingsCreateExpandableSection(cChar, {
		name = L["combatLogSection"] or "Combat logging",
		expanded = false,
		colorizeTitle = false,
	})

	local combatLogEnabled = addon.functions.SettingsCreateCheckbox(cChar, {
		var = "autoCombatLog",
		text = L["combatLogAuto"] or "Auto combat logging in instances",
		desc = L["combatLogAutoDesc"],
		func = function(value)
			addon.db.autoCombatLog = value and true or false
			if addon.functions.UpdateCombatLogState then addon.functions.UpdateCombatLogState() end
		end,
		parentSection = combatLogSection,
	})

	local function isCombatLogEnabled() return combatLogEnabled and combatLogEnabled.setting and combatLogEnabled.setting:GetValue() == true end

	addon.functions.SettingsCreateCheckbox(cChar, {
		var = "combatLogDelayedStop",
		text = L["combatLogDelayStop"] or "Delayed log stop",
		desc = L["combatLogDelayStopDesc"],
		func = function(value) addon.db.combatLogDelayedStop = value and true or false end,
		element = combatLogEnabled.element,
		parentSection = combatLogSection,
		parentCheck = isCombatLogEnabled,
		parent = true,
	})

	local function createCombatLogToggle(var, label, desc)
		addon.functions.SettingsCreateCheckbox(cChar, {
			var = var,
			text = label,
			desc = desc,
			func = function(value)
				addon.db[var] = value and true or false
				if addon.db.autoCombatLog and addon.functions.UpdateCombatLogState then addon.functions.UpdateCombatLogState() end
			end,
			element = combatLogEnabled.element,
			parentSection = combatLogSection,
			parentCheck = isCombatLogEnabled,
			parent = true,
		})
	end

	createCombatLogToggle("combatLogPvp", L["combatLogPvp"] or "PvP", L["combatLogPvpDesc"] or "Automatically toggle combat logging in PvP instances.")
	createCombatLogToggle("combatLogScenario", L["combatLogScenario"] or "Scenarios", L["combatLogScenarioDesc"] or "Automatically toggle combat logging in scenarios.")
	createCombatLogToggle("combatLogDelve", L["combatLogDelve"] or "Delves", L["combatLogDelveDesc"] or "Automatically toggle combat logging in delves.")

	local function createCombatLogDropdown(var, label, category)
		addon.functions.SettingsCreateMultiDropdown(cChar, {
			var = var,
			text = label,
			desc = L["combatLogListDesc"],
			listFunc = function() return getCombatLogDifficultyOptions(category) end,
			isSelectedFunc = function(key) return isCombatLogSelected(category, key) end,
			setSelectedFunc = function(key, selected) setCombatLogSelection(category, key, selected) end,
			menuHeight = 260,
			element = combatLogEnabled.element,
			parentSection = combatLogSection,
			parentCheck = isCombatLogEnabled,
			isEnabled = isCombatLogEnabled,
		})
	end

	createCombatLogDropdown("combatLogDungeonDifficulties", L["combatLogDungeon"] or "Dungeons", "dungeon")
	createCombatLogDropdown("combatLogRaidDifficulties", L["combatLogRaid"] or "Raids", "raid")

	local find = {
		["CLICK EQOLWorldMarkerCycler:LeftButton"] = true,
		["CLICK EQOLWorldMarkerCycler:RightButton"] = true,
	}
	addon.variables.keybindFindings = addon.functions.FindBindingIndex(find)

	-- Markers
	local sectionMarkers = addon.SettingsLayout.gameplayMarkersSection
	if not sectionMarkers then
		sectionMarkers = addon.functions.SettingsCreateExpandableSection(cChar, {
			name = L["Markers"],
			expanded = false,
			colorizeTitle = false,
		})
		addon.SettingsLayout.gameplayMarkersSection = sectionMarkers
	end

	if addon.variables.keybindFindings and next(addon.variables.keybindFindings) then
		if not sectionMarkers then
			sectionMarkers = addon.functions.SettingsCreateExpandableSection(addon.SettingsLayout.characterInspectCategory, {
				name = L["Markers"],
				expanded = false,
				colorizeTitle = false,
			})
			addon.SettingsLayout.gameplayMarkersSection = sectionMarkers
		end
		addon.functions.SettingsCreateHeadline(addon.SettingsLayout.characterInspectCategory, L["WorldMarkers"], {
			parentSection = sectionMarkers,
		})
		addon.functions.SettingsCreateText(addon.SettingsLayout.characterInspectCategory, "|cff99e599" .. L["WorldMarkerCycle"] .. "|r", { parentSection = sectionMarkers })
	end
	for _, v in pairs(addon.variables.keybindFindings) do
		addon.functions.SettingsCreateKeybind(addon.SettingsLayout.characterInspectCategory, v, sectionMarkers)
	end

	if LFGListFrame and LFGListFrame.SearchPanel and LFGListFrame.SearchPanel.FilterButton and LFGListFrame.SearchPanel.FilterButton.ResetButton then
		lfgPoint, lfgRelativeTo, lfgRelativePoint, lfgXOfs, lfgYOfs = LFGListFrame.SearchPanel.FilterButton.ResetButton:GetPoint()
	end
	if addon.db["groupfinderMoveResetButton"] then toggleLFGFilterPosition() end

	-- Add Raider.IO URL to LFG applicant member context menu
	if Menu and Menu.ModifyMenu then
		local regionTable = { "US", "KR", "EU", "TW", "CN" }
		local function trimNamePart(value)
			if issecretvalue and issecretvalue(value) then return nil end
			if type(value) ~= "string" then return nil end
			value = value:gsub("^%s+", ""):gsub("%s+$", "")
			if value == "" then return nil end
			return value
		end

		local function AddLFGApplicantRIO(owner, root, ctx)
			if not addon.db["enableChatIMRaiderIO"] then return end

			local appID = owner and owner._eqolApplicantID or (ctx and (ctx.applicantID or ctx.appID))
			local memberIdx = owner and owner._eqolMemberIdx or (ctx and (ctx.memberIdx or ctx.memberIndex))
			if issecretvalue and (issecretvalue(appID) or issecretvalue(memberIdx)) then return end
			if not appID or not memberIdx then return end

			local name = C_LFGList and C_LFGList.GetApplicantMemberInfo and C_LFGList.GetApplicantMemberInfo(appID, memberIdx)
			if issecretvalue and issecretvalue(name) then return end
			if type(name) ~= "string" or name == "" then return end

			local char, realm = name:match("^%s*([^%-]+)%s*%-%s*(.-)%s*$")
			char = trimNamePart(char) or trimNamePart(name)
			realm = trimNamePart(realm) or trimNamePart(GetRealmName() or "")
			if not char or not realm then return end

			local regionKey = regionTable[GetCurrentRegion()] or "EU"
			local realmSlug = realm:gsub("%s+", "-"):lower()
			local riolink = "https://raider.io/characters/" .. string.lower(regionKey) .. "/" .. realmSlug .. "/" .. char

			root:CreateDivider()
			root:CreateButton(L["RaiderIOUrl"], function(link)
				if StaticPopup_Show then StaticPopup_Show("EQOL_URL_COPY", nil, nil, link) end
			end, riolink)
		end

		Menu.ModifyMenu("MENU_LFG_FRAME_MEMBER_APPLY", AddLFGApplicantRIO)
	end

	_G["BINDING_NAME_CLICK EQOLWorldMarkerCycler:LeftButton"] = L["Cycle World Marker"]
	_G["BINDING_NAME_CLICK EQOLWorldMarkerCycler:RightButton"] = L["Clear World Marker"]

	local btn = CreateFrame("Button", "EQOLWorldMarkerCycler", UIParent, "SecureActionButtonTemplate")
	btn:SetAttribute("type", "macro")
	btn:RegisterForClicks("AnyUp", "AnyDown")
	local body = "i = 0;order = newtable()"
	for i = 1, 8 do
		body = body .. format("\ntinsert(order, %s)", i)
	end
	SecureHandlerExecute(btn, body)

	SecureHandlerUnwrapScript(btn, "PreClick")
	-- TODO check midnight later, /cwm 0 not working for now

	SecureHandlerWrapScript(
		btn,
		"PreClick",
		btn,
		[=[
		if not down or not next(order) then return end
		if button == "RightButton" then
			i = 0
			self:SetAttribute("macrotext", "/cwm all")
		else
			i = i%#order + 1
			self:SetAttribute("macrotext", "/wm [@cursor]"..order[i])
		end
	]=]
	)

	local expandable = addon.SettingsLayout.gameplayConvenienceSection
	if not expandable then
		expandable = addon.functions.SettingsCreateExpandableSection(addon.SettingsLayout.characterInspectCategory, {
			name = L["MacrosAndConsumables"] or "Macros & Consumables",
			newTagID = "MacrosAndConsumables",
			expanded = false,
			colorizeTitle = false,
		})
		addon.SettingsLayout.gameplayConvenienceSection = expandable
	end
	if addon.functions.initDrinkMacro then addon.functions.initDrinkMacro() end

	addon.functions.SettingsCreateHeadline(addon.SettingsLayout.characterInspectCategory, L["Mounts"] or "Mounts", { parentSection = expandable })
	addon.functions.SettingsCreateCheckbox(addon.SettingsLayout.characterInspectCategory, {
		var = "randomMountUseAll",
		text = L["Use all mounts for random mount"] or "Use all mounts for random mount",
		func = function(value)
			addon.db["randomMountUseAll"] = value and true or false
			if addon.MountActions and addon.MountActions.MarkRandomCacheDirty then addon.MountActions:MarkRandomCacheDirty() end
		end,
		default = false,
		parentSection = expandable,
	})

	addon.functions.SettingsCreateCheckbox(addon.SettingsLayout.characterInspectCategory, {
		var = "randomMountDracthyrVisageBeforeMount",
		text = L["randomMountDracthyrVisageBeforeMount"] or "Turn to Visage form as Dracthyr before mounting",
		desc = L["randomMountDracthyrVisageBeforeMountDesc"] or "Only applies to Dracthyr characters.",
		func = function(value) addon.db["randomMountDracthyrVisageBeforeMount"] = value and true or false end,
		default = false,
		parentSection = expandable,
	})

	addon.functions.SettingsCreateCheckbox(addon.SettingsLayout.characterInspectCategory, {
		var = "randomMountCastSlowFallWhenFalling",
		text = L["randomMountCastSlowFallWhenFalling"] or "Cast Slow Fall/Levitate/Travel Form while falling",
		desc = L["randomMountCastSlowFallWhenFallingDesc"] or "Only applies to Mages (Slow Fall), Druids (Travel Form) and Priests (Levitate).",
		func = function(value) addon.db["randomMountCastSlowFallWhenFalling"] = value and true or false end,
		default = false,
		parentSection = expandable,
	})

	addon.functions.SettingsCreateCheckbox(addon.SettingsLayout.characterInspectCategory, {
		var = "randomMountDruidNoShiftWhileMounted",
		text = L["randomMountDruidNoShiftWhileMounted"],
		func = function(value) addon.db["randomMountDruidNoShiftWhileMounted"] = value and true or false end,
		default = false,
		parentSection = expandable,
	})

	addon.functions.SettingsCreateHeadline(addon.SettingsLayout.characterInspectCategory, C_CreatureInfo.GetClassInfo(11).className, { parentSection = expandable })

	local data = {
		{
			var = "autoCancelDruidFlightForm",
			text = L["autoCancelDruidFlightForm"],
			desc = L["autoCancelDruidFlightFormDesc"],
			func = function(value)
				addon.db["autoCancelDruidFlightForm"] = value and true or false
				if addon.functions.updateDruidFlightFormWatcher then addon.functions.updateDruidFlightFormWatcher() end
			end,
			parentSection = expandable,
		},
	}

	addon.functions.SettingsCreateCheckboxes(addon.SettingsLayout.characterInspectCategory, data)
end

---- END REGION

---- REGION SETTINGS

-- Dungeons & Mythic+
local sectionDungeon = addon.SettingsLayout.gameplayDungeonsMythicSection
if not sectionDungeon then
	sectionDungeon = addon.functions.SettingsCreateExpandableSection(cChar, {
		name = L["DungeonsMythicPlus"],
		expanded = false,
		colorizeTitle = false,
		newTagID = "DungeonsMythicPlus",
	})
	addon.SettingsLayout.gameplayDungeonsMythicSection = sectionDungeon
end

-- Mythic+ & Raid (Combat & Dungeon)
local keystoneEnable
local function isKeystoneEnabled() return keystoneEnable and keystoneEnable.setting and keystoneEnable.setting:GetValue() == true end

if cChar and sectionDungeon then
	addon.functions.SettingsCreateHeadline(cChar, PLAYER_DIFFICULTY_MYTHIC_PLUS .. " & " .. RAID, { parentSection = sectionDungeon })

	-- Keystone Helper
	keystoneEnable = addon.functions.SettingsCreateCheckbox(cChar, {
		var = "enableKeystoneHelper",
		text = LMP["enableKeystoneHelper"],
		desc = LMP["enableKeystoneHelperDesc"],
		func = function(v)
			addon.db["enableKeystoneHelper"] = v
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.toggleFrame then addon.MythicPlus.functions.toggleFrame() end
		end,
		parentSection = sectionDungeon,
	})

	local keystoneChildren = {
		{ var = "autoInsertKeystone", text = LMP["Automatically insert keystone"], func = function(v) addon.db["autoInsertKeystone"] = v end, parentSection = sectionDungeon },
		{ var = "closeBagsOnKeyInsert", text = LMP["Close all bags on keystone insert"], func = function(v) addon.db["closeBagsOnKeyInsert"] = v end, parentSection = sectionDungeon },
		{ var = "autoKeyStart", text = LMP["autoKeyStart"], func = function(v) addon.db["autoKeyStart"] = v end, parentSection = sectionDungeon },
		{
			var = "mythicPlusShowChestTimers",
			text = LMP["mythicPlusShowChestTimers"],
			desc = LMP["mythicPlusShowChestTimersDesc"],
			func = function(v) addon.db["mythicPlusShowChestTimers"] = v end,
			parentSection = sectionDungeon,
		},
	}
	for _, entry in ipairs(keystoneChildren) do
		entry.parent = true
		entry.element = keystoneEnable.element
		entry.parentCheck = isKeystoneEnabled
		addon.functions.SettingsCreateCheckbox(cChar, entry)
	end

	local listPull, orderPull = addon.functions.prepareListForDropdown({
		[1] = LMP["None"],
		[2] = LMP["Blizzard Pull Timer"],
		[3] = LMP["DBM / BigWigs Pull Timer"],
		[4] = LMP["Both"],
	})
	addon.functions.SettingsCreateDropdown(cChar, {
		var = "PullTimerType",
		text = LMP["PullTimer"],
		type = Settings.VarType.Number,
		default = 2,
		list = listPull,
		order = orderPull,
		get = function() return (addon.db and addon.db["PullTimerType"]) or 1 end,
		set = function(value) addon.db["PullTimerType"] = value end,
		parent = true,
		element = keystoneEnable.element,
		parentCheck = isKeystoneEnabled,
		parentSection = sectionDungeon,
	})

	addon.functions.SettingsCreateCheckbox(cChar, {
		var = "noChatOnPullTimer",
		text = LMP["noChatOnPullTimer"],
		func = function(v) addon.db["noChatOnPullTimer"] = v end,
		parent = true,
		element = keystoneEnable.element,
		parentCheck = isKeystoneEnabled,
		parentSection = sectionDungeon,
	})

	addon.functions.SettingsCreateSlider(cChar, {
		var = "pullTimerLongTime",
		text = LMP["sliderLongTime"],
		min = 0,
		max = 60,
		step = 1,
		default = 10,
		get = function() return (addon.db and addon.db["pullTimerLongTime"]) or 10 end,
		set = function(val) addon.db["pullTimerLongTime"] = val end,
		parent = true,
		element = keystoneEnable.element,
		parentCheck = isKeystoneEnabled,
		parentSection = sectionDungeon,
	})

	addon.functions.SettingsCreateSlider(cChar, {
		var = "pullTimerShortTime",
		text = LMP["sliderShortTime"],
		min = 0,
		max = 60,
		step = 1,
		default = 5,
		get = function() return (addon.db and addon.db["pullTimerShortTime"]) or 5 end,
		set = function(val) addon.db["pullTimerShortTime"] = val end,
		parent = true,
		element = keystoneEnable.element,
		parentCheck = isKeystoneEnabled,
		parentSection = sectionDungeon,
	})

	-- Objective Tracker
	local objEnable = addon.functions.SettingsCreateCheckbox(cChar, {
		var = "mythicPlusEnableObjectiveTracker",
		text = LMP["mythicPlusEnableObjectiveTracker"],
		desc = LMP["mythicPlusEnableObjectiveTrackerDesc"],
		func = function(v)
			addon.db["mythicPlusEnableObjectiveTracker"] = v
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.setObjectiveFrames then addon.MythicPlus.functions.setObjectiveFrames() end
		end,
		parentSection = sectionDungeon,
	})
	local function isObjectiveEnabled() return objEnable and objEnable.setting and objEnable.setting:GetValue() == true end

	local listObj, orderObj = addon.functions.prepareListForDropdown({ [1] = LMP["HideTracker"], [2] = LMP["collapse"] })
	addon.functions.SettingsCreateDropdown(cChar, {
		var = "mythicPlusObjectiveTrackerSetting",
		text = LMP["mythicPlusObjectiveTrackerSetting"],
		type = Settings.VarType.Number,
		default = (addon.db and addon.db["mythicPlusObjectiveTrackerSetting"]) or 1,
		list = listObj,
		order = orderObj,
		get = function() return (addon.db and addon.db["mythicPlusObjectiveTrackerSetting"]) or 1 end,
		set = function(value)
			addon.db["mythicPlusObjectiveTrackerSetting"] = value
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.setObjectiveFrames then addon.MythicPlus.functions.setObjectiveFrames() end
		end,
		parent = true,
		element = objEnable.element,
		parentCheck = isObjectiveEnabled,
		parentSection = sectionDungeon,
	})

	-- BR Tracker
	addon.functions.SettingsCreateCheckbox(cChar, {
		var = "mythicPlusBRTrackerEnabled",
		text = LMP["mythicPlusBRTrackerEnabled"],
		desc = LMP["mythicPlusBRTrackerEditModeHint"],
		func = function(v)
			addon.db["mythicPlusBRTrackerEnabled"] = v
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.createBRFrame then
				addon.MythicPlus.functions.createBRFrame()
			elseif addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.setObjectiveFrames then
				addon.MythicPlus.functions.setObjectiveFrames()
			end
		end,
		parentSection = sectionDungeon,
	})

	addon.functions.SettingsCreateCheckbox(cChar, {
		var = "mythicPlusBloodlustTrackerEnabled",
		text = LMP["mythicPlusBloodlustTrackerEnabled"],
		desc = LMP["mythicPlusBloodlustTrackerEditModeHint"],
		func = function(v)
			addon.db["mythicPlusBloodlustTrackerEnabled"] = v
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.syncBloodlustUnitAuraRegistration then addon.MythicPlus.functions.syncBloodlustUnitAuraRegistration() end
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.createBloodlustFrame then
				addon.MythicPlus.functions.createBloodlustFrame()
				if addon.MythicPlus.functions.refreshBloodlustTracker then addon.MythicPlus.functions.refreshBloodlustTracker(false) end
			end
		end,
		parentSection = sectionDungeon,
	})
end

data = {
	{
		var = "autoChooseDelvePower",
		text = L["autoChooseDelvePower"],
		func = function(value) addon.db["autoChooseDelvePower"] = value and true or false end,
		parentSection = sectionDungeon,
	},
}
table.sort(data, function(a, b) return a.text < b.text end)

addon.functions.SettingsCreateHeadline(cChar, DELVES_LABEL, { parentSection = sectionDungeon })
addon.functions.SettingsCreateCheckboxes(cChar, data)

-- Group Finder
local sectionGroupFinder = addon.SettingsLayout.gameplayGroupFinderSection
if not sectionGroupFinder then
	sectionGroupFinder = addon.functions.SettingsCreateExpandableSection(cChar, {
		name = L["GroupFinder"],
		expanded = false,
		colorizeTitle = false,
	})
	addon.SettingsLayout.gameplayGroupFinderSection = sectionGroupFinder
end

data = {
	{
		text = L["groupfinderAppText"],
		var = "groupfinderAppText",
		func = function(value)
			addon.db["groupfinderAppText"] = value
			toggleGroupApplication(value)
		end,
		parentSection = sectionGroupFinder,
	},
	{
		text = L["groupfinderMoveResetButton"],
		var = "groupfinderMoveResetButton",
		func = function(value)
			addon.db["groupfinderMoveResetButton"] = value
			toggleLFGFilterPosition()
		end,
		parentSection = sectionGroupFinder,
	},
	{
		text = L["groupfinderSkipRoleSelect"],
		var = "groupfinderSkipRoleSelect",
		func = function(value) addon.db["groupfinderSkipRoleSelect"] = value end,
		desc = L["interruptWithShift"],
		parentSection = sectionGroupFinder,
		children = {
			{
				list = { [1] = L["groupfinderSkipRolecheckUseSpec"], [2] = L["groupfinderSkipRolecheckUseLFD"] },
				text = L["groupfinderSkipRolecheckHeadline"],
				get = function() return addon.db["groupfinderSkipRoleSelectOption"] or 1 end,
				set = function(key) addon.db["groupfinderSkipRoleSelectOption"] = key end,
				parentCheck = function()
					return addon.SettingsLayout.elements["groupfinderSkipRoleSelect"]
						and addon.SettingsLayout.elements["groupfinderSkipRoleSelect"].setting
						and addon.SettingsLayout.elements["groupfinderSkipRoleSelect"].setting:GetValue() == true
				end,
				parent = true,
				default = 1,
				var = "groupfinderSkipRoleSelectOption",
				type = Settings.VarType.Number,
				sType = "dropdown",
				parentSection = sectionGroupFinder,
			},
		},
	},
	{
		var = "persistSignUpNote",
		text = L["Persist LFG signup note"],
		func = function(value) addon.db["persistSignUpNote"] = value end,
		parentSection = sectionGroupFinder,
	},
	{
		var = "skipSignUpDialog",
		text = L["Quick signup"],
		func = function(value) addon.db["skipSignUpDialog"] = value end,
		parentSection = sectionGroupFinder,
	},
	{
		var = "lfgSortByRio",
		text = L["lfgSortByRio"],
		func = function(value) addon.db["lfgSortByRio"] = value end,
		parentSection = sectionGroupFinder,
	},
	{
		var = "enableChatIMRaiderIO",
		text = L["enableChatIMRaiderIO"],
		func = function(value) addon.db["enableChatIMRaiderIO"] = value end,
		parentSection = sectionGroupFinder,
	},
}

if keystoneEnable then
	table.insert(data, {
		var = "groupfinderShowPartyKeystone",
		text = LMP["groupfinderShowPartyKeystone"],
		desc = LMP["groupfinderShowPartyKeystoneDesc"],
		func = function(v)
			addon.db["groupfinderShowPartyKeystone"] = v
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.togglePartyKeystone then addon.MythicPlus.functions.togglePartyKeystone() end
		end,
		parent = true,
		element = keystoneEnable.element,
		parentCheck = isKeystoneEnabled,
		parentSection = sectionGroupFinder,
	})
end

table.insert(data, {
	var = "groupfinderShowDungeonScoreFrame",
	text = LMP["groupfinderShowDungeonScoreFrame"]:format(DUNGEON_SCORE),
	func = function(v)
		addon.db["groupfinderShowDungeonScoreFrame"] = v
		if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.toggleFrame then addon.MythicPlus.functions.toggleFrame() end
	end,
	parentSection = sectionGroupFinder,
})

table.insert(data, {
	var = "mythicPlusEnableDungeonFilter",
	text = LMP["mythicPlusEnableDungeonFilter"],
	desc = LMP["mythicPlusEnableDungeonFilterDesc"]:format(REPORT_GROUP_FINDER_ADVERTISEMENT),
	func = function(v)
		addon.db["mythicPlusEnableDungeonFilter"] = v
		if addon.MythicPlus and addon.MythicPlus.functions then
			if v and addon.MythicPlus.functions.addDungeonFilter then
				addon.MythicPlus.functions.addDungeonFilter()
			elseif not v and addon.MythicPlus.functions.removeDungeonFilter then
				addon.MythicPlus.functions.removeDungeonFilter()
			end
		end
	end,
	parentSection = sectionGroupFinder,
	children = {
		{
			var = "mythicPlusEnableDungeonFilterClearReset",
			text = LMP["mythicPlusEnableDungeonFilterClearReset"],
			func = function(v) addon.db["mythicPlusEnableDungeonFilterClearReset"] = v end,
			parentCheck = function()
				return addon.SettingsLayout.elements["mythicPlusEnableDungeonFilter"]
					and addon.SettingsLayout.elements["mythicPlusEnableDungeonFilter"].setting
					and addon.SettingsLayout.elements["mythicPlusEnableDungeonFilter"].setting:GetValue() == true
			end,
			parent = true,
			default = false,
			type = Settings.VarType.Boolean,
			sType = "checkbox",
			parentSection = sectionGroupFinder,
		},
	},
})

table.sort(data, function(a, b) return a.text < b.text end)
addon.functions.SettingsCreateCheckboxes(cChar, data)

-- Death & Resurrect
local sectionDeathRes = addon.SettingsLayout.gameplayDeathResSection
if not sectionDeathRes then
	sectionDeathRes = addon.functions.SettingsCreateExpandableSection(cChar, {
		name = L["DeathResurrect"],
		newTagID = "DeathResurrect",
		expanded = false,
		colorizeTitle = false,
	})
	addon.SettingsLayout.gameplayDeathResSection = sectionDeathRes
end

addon.functions.SettingsCreateHeadline(cChar, L["ReleaseTimer"], { parentSection = sectionDeathRes })

data = {
	var = "timeoutRelease",
	text = L["timeoutRelease"],
	func = function(value) addon.db["timeoutRelease"] = value end,
	parentSection = sectionDeathRes,
}
table.sort(data, function(a, b) return a.text < b.text end)

local rData = addon.functions.SettingsCreateCheckbox(cChar, data)

data = {
	list = {
		SHIFT = SHIFT_KEY_TEXT,
		CTRL = CTRL_KEY_TEXT,
		ALT = ALT_KEY_TEXT,
	},
	text = L["timeoutReleaseModifierLabel"],
	get = function() return addon.db["timeoutReleaseModifier"] or "SHIFT" end,
	set = function(key) addon.db["timeoutReleaseModifier"] = key end,
	parentCheck = function() return rData.setting and rData.setting:GetValue() == true end,
	element = rData.element,
	parent = true,
	default = "SHIFT",
	var = "timeoutReleaseModifier",
	parentSection = sectionDeathRes,
}

addon.functions.SettingsCreateDropdown(cChar, data)

local timeoutReleaseGroups = {
	{
		var = "timeoutRelease_raidNormal",
		value = "raidNormal",
		text = RAID .. " - " .. PLAYER_DIFFICULTY1 .. " / " .. PLAYER_DIFFICULTY3 .. " / " .. PLAYER_DIFFICULTY_TIMEWALKER,
		func = function(value) addon.db["timeoutReleaseDifficulties"]["raidNormal"] = value and true or false end,
		get = function() return addon.db["timeoutReleaseDifficulties"]["raidNormal"] end,
		parentCheck = function() return rData.setting and rData.setting:GetValue() == true end,
		element = rData.element,
		parent = true,
		difficulties = { 3, 4, 7, 9, 14, 17, 18, 33, 151, 220 },
	},
	{
		var = "timeoutRelease_raidHeroic",
		value = "raidHeroic",
		text = RAID .. " - " .. PLAYER_DIFFICULTY2,
		func = function(value) addon.db["timeoutReleaseDifficulties"]["raidHeroic"] = value and true or false end,
		get = function() return addon.db["timeoutReleaseDifficulties"]["raidHeroic"] end,
		parentCheck = function() return rData.setting and rData.setting:GetValue() == true end,
		element = rData.element,
		parent = true,
		difficulties = { 5, 6, 15 },
	},
	{
		var = "timeoutRelease_raidMythic",
		value = "raidMythic",
		text = RAID .. " - " .. PLAYER_DIFFICULTY6,
		func = function(value) addon.db["timeoutReleaseDifficulties"]["raidMythic"] = value and true or false end,
		get = function() return addon.db["timeoutReleaseDifficulties"]["raidMythic"] end,
		parentCheck = function() return rData.setting and rData.setting:GetValue() == true end,
		element = rData.element,
		parent = true,
		difficulties = { 16 },
	},
	{
		var = "timeoutRelease_dungeonNormal",
		value = "dungeonNormal",
		text = DUNGEONS .. " - " .. PLAYER_DIFFICULTY1 .. " / " .. PLAYER_DIFFICULTY_TIMEWALKER,
		func = function(value) addon.db["timeoutReleaseDifficulties"]["dungeonNormal"] = value and true or false end,
		get = function() return addon.db["timeoutReleaseDifficulties"]["dungeonNormal"] end,
		parentCheck = function() return rData.setting and rData.setting:GetValue() == true end,
		element = rData.element,
		parent = true,
		difficulties = { 1, 24, 150, 216 },
	},
	{
		var = "timeoutRelease_dungeonHeroic",
		value = "dungeonHeroic",
		text = DUNGEONS .. " - " .. PLAYER_DIFFICULTY2,
		func = function(value) addon.db["timeoutReleaseDifficulties"]["dungeonHeroic"] = value and true or false end,
		get = function() return addon.db["timeoutReleaseDifficulties"]["dungeonHeroic"] end,
		parentCheck = function() return rData.setting and rData.setting:GetValue() == true end,
		element = rData.element,
		parent = true,
		difficulties = { 2 },
	},
	{
		var = "timeoutRelease_dungeonMythic",
		value = "dungeonMythic",
		text = DUNGEONS .. " - " .. PLAYER_DIFFICULTY6,
		func = function(value) addon.db["timeoutReleaseDifficulties"]["dungeonMythic"] = value and true or false end,
		get = function() return addon.db["timeoutReleaseDifficulties"]["dungeonMythic"] end,
		parentCheck = function() return rData.setting and rData.setting:GetValue() == true end,
		element = rData.element,
		parent = true,
		difficulties = { 23 },
	},
	{
		var = "timeoutRelease_dungeonMythicPlus",
		value = "dungeonMythicPlus",
		text = DUNGEONS .. " - " .. PLAYER_DIFFICULTY_MYTHIC_PLUS,
		func = function(value) addon.db["timeoutReleaseDifficulties"]["dungeonMythicPlus"] = value and true or false end,
		get = function() return addon.db["timeoutReleaseDifficulties"]["dungeonMythicPlus"] end,
		parentCheck = function() return rData.setting and rData.setting:GetValue() == true end,
		element = rData.element,
		parent = true,
		difficulties = { 8 },
	},
	{
		var = "timeoutRelease_dungeonFollower",
		value = "dungeonFollower",
		text = GUILD_CHALLENGE_TYPE4 .. " - " .. L["timeoutReleasePrefixScenario"],
		func = function(value) addon.db["timeoutReleaseDifficulties"]["dungeonFollower"] = value and true or false end,
		get = function() return addon.db["timeoutReleaseDifficulties"]["dungeonFollower"] end,
		parentCheck = function() return rData.setting and rData.setting:GetValue() == true end,
		element = rData.element,
		parent = true,
		difficulties = { 11, 12, 20, 30, 38, 39, 40, 147, 149, 152, 153, 167, 168, 169, 170, 171, 208 },
	},
	{
		var = "timeoutRelease_pvp",
		value = "pvp",
		text = PVP,
		func = function(value) addon.db["timeoutReleaseDifficulties"]["pvp"] = value and true or false end,
		get = function() return addon.db["timeoutReleaseDifficulties"]["pvp"] end,
		parentCheck = function() return rData.setting and rData.setting:GetValue() == true end,
		element = rData.element,
		parent = true,
		difficulties = { 29, 34, 45 },
	},
	{
		var = "timeoutRelease_world",
		value = "world",
		text = WORLD,
		func = function(value) addon.db["timeoutReleaseDifficulties"]["world"] = value and true or false end,
		get = function() return addon.db["timeoutReleaseDifficulties"]["world"] end,
		parentCheck = function() return rData.setting and rData.setting:GetValue() == true end,
		element = rData.element,
		parent = true,
		difficulties = { 0, 172, 192 },
	},
}

for _, group in ipairs(timeoutReleaseGroups) do
	if group.difficulties then
		group.difficultySet = {}
		for _, difficultyID in ipairs(group.difficulties) do
			group.difficultySet[difficultyID] = true
			local bucket = timeoutReleaseDifficultyLookup[difficultyID]
			if not bucket then
				timeoutReleaseDifficultyLookup[difficultyID] = { group.key }
			else
				table.insert(bucket, group.key)
			end
		end
	end
end

addon.functions.SettingsCreateMultiDropdown(cChar, {
	var = "timeoutReleaseDifficulties",
	text = L["timeoutReleaseHeadline"],
	parent = true,
	element = rData.element,
	parentCheck = function() return rData.setting and rData.setting:GetValue() == true end,
	options = timeoutReleaseGroups,
	parentSection = sectionDeathRes,
})

local function isAutoAcceptResurrectionEnabled()
	return addon.SettingsLayout.elements["autoAcceptResurrection"]
		and addon.SettingsLayout.elements["autoAcceptResurrection"].setting
		and addon.SettingsLayout.elements["autoAcceptResurrection"].setting:GetValue() == true
end

addon.functions.SettingsCreateHeadline(cChar, L["Resurrection"], { parentSection = sectionDeathRes })

addon.functions.SettingsCreateCheckbox(cChar, {
	var = "autoAcceptResurrection",
	text = L["autoAcceptResurrection"],
	desc = L["autoAcceptResurrectionDesc"],
	func = function(value) addon.db["autoAcceptResurrection"] = value end,
	parentSection = sectionDeathRes,
	children = {
		{
			var = "autoAcceptResurrectionExcludeCombat",
			text = L["autoAcceptResurrectionExcludeCombat"],
			func = function(v) addon.db["autoAcceptResurrectionExcludeCombat"] = v end,
			parentCheck = isAutoAcceptResurrectionEnabled,
			parent = true,
			default = true,
			type = Settings.VarType.Boolean,
			sType = "checkbox",
			parentSection = sectionDeathRes,
		},
		{
			var = "autoAcceptResurrectionExcludeAfterlife",
			text = L["autoAcceptResurrectionExcludeAfterlife"],
			func = function(v) addon.db["autoAcceptResurrectionExcludeAfterlife"] = v end,
			parentCheck = isAutoAcceptResurrectionEnabled,
			parent = true,
			default = true,
			type = Settings.VarType.Boolean,
			sType = "checkbox",
			parentSection = sectionDeathRes,
		},
	},
})

local function isAutoReleasePvPEnabled()
	return addon.SettingsLayout.elements["autoReleasePvP"] and addon.SettingsLayout.elements["autoReleasePvP"].setting and addon.SettingsLayout.elements["autoReleasePvP"].setting:GetValue() == true
end

addon.functions.SettingsCreateHeadline(cChar, L["PvPAutoRelease"], { parentSection = sectionDeathRes })

addon.functions.SettingsCreateCheckbox(cChar, {
	var = "autoReleasePvP",
	text = L["autoReleasePvP"],
	desc = L["autoReleasePvPDesc"],
	func = function(value) addon.db["autoReleasePvP"] = value end,
	parentSection = sectionDeathRes,
	children = {
		{
			var = "autoReleasePvPDelay",
			text = L["autoReleasePvPDelay"],
			desc = L["autoReleasePvPDelayDesc"],
			get = function() return addon.db and addon.db.autoReleasePvPDelay or 0 end,
			set = function(value) addon.db["autoReleasePvPDelay"] = value end,
			min = 0,
			max = 3000,
			step = 100,
			parentCheck = isAutoReleasePvPEnabled,
			parent = true,
			default = 0,
			sType = "slider",
			parentSection = sectionDeathRes,
		},
		{
			var = "autoReleasePvPExcludeAlterac",
			text = L["autoReleasePvPExcludeAlterac"],
			func = function(v) addon.db["autoReleasePvPExcludeAlterac"] = v end,
			parentCheck = isAutoReleasePvPEnabled,
			parent = true,
			default = false,
			type = Settings.VarType.Boolean,
			sType = "checkbox",
			parentSection = sectionDeathRes,
		},
		{
			var = "autoReleasePvPExcludeWintergrasp",
			text = L["autoReleasePvPExcludeWintergrasp"],
			func = function(v) addon.db["autoReleasePvPExcludeWintergrasp"] = v end,
			parentCheck = isAutoReleasePvPEnabled,
			parent = true,
			default = false,
			type = Settings.VarType.Boolean,
			sType = "checkbox",
			parentSection = sectionDeathRes,
		},
		{
			var = "autoReleasePvPExcludeTolBarad",
			text = L["autoReleasePvPExcludeTolBarad"],
			func = function(v) addon.db["autoReleasePvPExcludeTolBarad"] = v end,
			parentCheck = isAutoReleasePvPEnabled,
			parent = true,
			default = false,
			type = Settings.VarType.Boolean,
			sType = "checkbox",
			parentSection = sectionDeathRes,
		},
		{
			var = "autoReleasePvPExcludeAshran",
			text = L["autoReleasePvPExcludeAshran"],
			func = function(v) addon.db["autoReleasePvPExcludeAshran"] = v end,
			parentCheck = isAutoReleasePvPEnabled,
			parent = true,
			default = false,
			type = Settings.VarType.Boolean,
			sType = "checkbox",
			parentSection = sectionDeathRes,
		},
	},
})

---- REGION END

local eventHandlers = {

	["LFG_LIST_APPLICANT_UPDATED"] = function()
		if PVEFrame:IsShown() and addon.db["lfgSortByRio"] and not addon.functions.isRestrictedContent() then C_LFGList.RefreshApplicants() end
		if InCombatLockdown() then return end
		if addon.db["groupfinderAppText"] then toggleGroupApplication(true) end
	end,
	["PLAYER_DIFFICULTY_CHANGED"] = function()
		if addon.functions.UpdateCombatLogState then addon.functions.UpdateCombatLogState() end
	end,
	["PLAYER_ENTERING_WORLD"] = function()
		if addon.functions.UpdateCombatLogState then addon.functions.UpdateCombatLogState() end
	end,
	["ZONE_CHANGED_NEW_AREA"] = function()
		if addon.functions.UpdateCombatLogState then addon.functions.UpdateCombatLogState() end
	end,
	["MODIFIER_STATE_CHANGED"] = function(arg1, arg2)
		if not addon.db["timeoutRelease"] then return end
		if not UnitIsDead("player") then return end
		local modifierKey = addon.functions.getTimeoutReleaseModifierKey()
		if not (arg1 and arg1:match(modifierKey)) then return end

		local _, stp = StaticPopup_Visible("DEATH")
		if stp and stp.GetButton and addon.functions.shouldUseTimeoutReleaseForCurrentContext() then
			local btn = stp:GetButton(1)
			if btn then btn:SetAlpha(arg2 or 0) end
		end
	end,
	["PLAYER_CHOICE_UPDATE"] = function()
		if select(3, GetInstanceInfo()) == 208 and addon.db["autoChooseDelvePower"] then
			local choiceInfo = C_PlayerChoice.GetCurrentPlayerChoiceInfo()
			if choiceInfo and choiceInfo.options and #choiceInfo.options == 1 then
				C_PlayerChoice.SendPlayerChoiceResponse(choiceInfo.options[1].buttons[1].id)
				if PlayerChoiceFrame:IsShown() then PlayerChoiceFrame:Hide() end
			end
		end
	end,
	["UPDATE_INSTANCE_INFO"] = function()
		if addon.functions.UpdateCombatLogState then addon.functions.UpdateCombatLogState() end
	end,
}

local function registerEvents(frame)
	for event in pairs(eventHandlers) do
		frame:RegisterEvent(event)
	end
end

local function eventHandler(self, event, ...)
	if eventHandlers[event] then eventHandlers[event](...) end
end

local frameLoad = CreateFrame("Frame")

registerEvents(frameLoad)
frameLoad:SetScript("OnEvent", eventHandler)
