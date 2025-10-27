-- luacheck: globals ScrollBoxListMixin EncounterJournal_LootUpdate EncounterJournal EJ_SelectInstance EJ_SetLootFilter EJ_SelectEncounter EJ_GetNumLoot EJ_GetDifficulty EJ_GetLootFilter
local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.DungeonJournalLootSpec = addon.DungeonJournalLootSpec or {}
local Module = addon.DungeonJournalLootSpec

Module.frame = Module.frame or CreateFrame("Frame")
Module.enabled = Module.enabled or false

local classes = {}
local roles = {}
local cache = { items = {} }
local numSpecs = 0
local fakeEveryoneSpec = { { specIcon = 922035 } }

local ROLES_ATLAS = {
	TANK = "UI-LFG-RoleIcon-Tank-Micro-GroupFinder",
	HEALER = "UI-LFG-RoleIcon-Healer-Micro-GroupFinder",
	DAMAGER = "UI-LFG-RoleIcon-DPS-Micro-GroupFinder",
}

local ANCHOR = {
	"TOPRIGHT",
	"BOTTOMRIGHT",
}

local ANCHORFLIP = {
	TOPRIGHT = "TOPLEFT",
	BOTTOMRIGHT = "BOTTOMLEFT",
}

local PADDINGFLIP = {
	TOPRIGHT = 1,
	BOTTOMRIGHT = 1,
	TOPLEFT = 1,
	BOTTOMLEFT = -1,
}

local ClampValue = Clamp or function(val, minValue, maxValue)
	if val < minValue then return minValue end
	if val > maxValue then return maxValue end
	return val
end

local function BuildClassData()
	wipe(classes)
	wipe(roles)
	numSpecs = 0

	for i = 1, GetNumClasses() do
		local classInfo = C_CreatureInfo.GetClassInfo(i)
		if classInfo and classInfo.classID then
			classInfo.numSpecs = GetNumSpecializationsForClassID(classInfo.classID) or 0
			classInfo.specs = {}
			classes[classInfo.classID] = classInfo

			for j = 1, classInfo.numSpecs do
				local specID, specName, _, specIcon, specRole = GetSpecializationInfoForClassID(classInfo.classID, j)
				if specID and specRole then
					local spec = {
						id = specID,
						name = specName,
						icon = specIcon,
						role = specRole,
					}
					classInfo.specs[specID] = spec
					numSpecs = numSpecs + 1
					roles[specRole] = roles[specRole] or {}
					roles[specRole][specID] = classInfo.classID
				end
			end
		end
	end

	for role, specToClass in pairs(roles) do
		local count = 0
		for specID, _ in pairs(specToClass) do
			if specID ~= "numSpecs" then count = count + 1 end
		end
		specToClass.numSpecs = count
	end
end

local function CompressSpecs(specs)
	local compress
	for classID, classInfo in pairs(classes) do
		local remaining = classInfo.numSpecs or 0
		if remaining > 0 then
			for specID, _ in pairs(classInfo.specs) do
				for _, info in ipairs(specs) do
					if info.specID == specID then
						remaining = remaining - 1
						break
					end
				end
				if remaining == 0 then break end
			end
			if remaining == 0 then
				compress = compress or {}
				compress[classID] = true
			end
		end
	end
	if not compress then return specs end

	local encountered = {}
	local compressed = {}
	local index = 0
	for _, info in ipairs(specs) do
		if compress[info.classID] then
			if not encountered[info.classID] then
				encountered[info.classID] = true
				index = index + 1
				info.specID = 0
				info.specName = info.className
				info.specIcon = true
				info.specRole = ""
				compressed[index] = info
			end
		else
			index = index + 1
			compressed[index] = info
		end
	end
	return compressed
end

local function CompressRoles(specs)
	local compress
	for role, specToClass in pairs(roles) do
		local remaining = specToClass.numSpecs or 0
		for specID, _ in pairs(specToClass) do
			for _, info in ipairs(specs) do
				if info.specID == specID then
					remaining = remaining - 1
					break
				end
			end
			if remaining == 0 then break end
		end
		if remaining == 0 then
			compress = compress or {}
			compress[role] = true
		end
	end
	if not compress then return specs end

	local encountered = {}
	local compressed = {}
	local index = 0
	for _, info in ipairs(specs) do
		if compress[info.specRole] then
			if not encountered[info.specRole] then
				encountered[info.specRole] = true
				index = index + 1
				info.specID = 0
				info.specName = info.specRole
				info.specIcon = true
				info.specRole = true
				compressed[index] = info
			end
		else
			index = index + 1
			compressed[index] = info
		end
	end
	return compressed
end

local function SortByClassAndSpec(a, b)
	if a.className == b.className then return a.specName < b.specName end
	return a.className < b.className
end

local function GetConfig()
	local db = addon.db or {}
	return {
		anchor = db["dungeonJournalLootSpecAnchor"] or 1,
		offsetX = db["dungeonJournalLootSpecOffsetX"] or 0,
		offsetY = db["dungeonJournalLootSpecOffsetY"] or 0,
		spacing = db["dungeonJournalLootSpecSpacing"] or 0,
		textureScale = db["dungeonJournalLootSpecScale"] or 1,
		iconPadding = db["dungeonJournalLootSpecIconPadding"] or 0,
		compressSpecs = db["dungeonJournalLootSpecCompressSpecs"] and true or false,
		compressRoles = db["dungeonJournalLootSpecCompressRoles"] and true or false,
		showAll = db["dungeonJournalLootSpecShowAll"] and true or false,
	}
end

local function GetSpecsForItem(button)
	local itemID = button and button.itemID
	if not itemID then return end

	local itemCache = cache.items[itemID]
	if not itemCache then return end

	if itemCache.everyone then return true end

	local config = GetConfig()
	local _, _, playerClassID = UnitClass("player")
	local specs = {}
	local index = 0

	for specID, classID in pairs(itemCache.specs) do
		if config.showAll or playerClassID == classID then
			local classInfo = classes[classID]
			local specInfo = classInfo and classInfo.specs and classInfo.specs[specID]
			if classInfo and specInfo then
				index = index + 1
				specs[index] = {
					classID = classID,
					className = classInfo.className,
					classFile = classInfo.classFile,
					specID = specID,
					specName = specInfo.name,
					specIcon = specInfo.icon,
					specRole = specInfo.role,
				}
			end
		end
	end

	if not specs[1] then return end

	if config.compressSpecs and specs[2] then specs = CompressSpecs(specs) end
	if config.compressRoles and specs[2] then specs = CompressRoles(specs) end
	if specs[2] then table.sort(specs, SortByClassAndSpec) end

	return specs
end

local function UpdateItems()
	if not EncounterJournal or not EncounterJournal.encounter then return end

	local difficulty = EJ_GetDifficulty and EJ_GetDifficulty()
	if cache.difficulty and cache.difficulty == difficulty and cache.instanceID == EncounterJournal.instanceID and cache.encounterID == EncounterJournal.encounterID then
		return
	end

	cache.difficulty = difficulty
	cache.instanceID = EncounterJournal.instanceID
	cache.encounterID = EncounterJournal.encounterID
	if EJ_GetLootFilter then cache.classID, cache.specID = EJ_GetLootFilter() end

	if not cache.instanceID then return end

	EJ_SelectInstance(cache.instanceID)
	wipe(cache.items)

	for classID, classData in pairs(classes) do
		for specID, _ in pairs(classData.specs) do
			EJ_SetLootFilter(classID, specID)
			for index = 1, EJ_GetNumLoot() or 0 do
				local itemInfo = C_EncounterJournal.GetLootInfoByIndex(index)
				if itemInfo and itemInfo.itemID then
					local itemCache = cache.items[itemInfo.itemID]
					if not itemCache then
						itemCache = itemInfo
						itemCache.specs = {}
						cache.items[itemInfo.itemID] = itemCache
					end
					itemCache.specs[specID] = classID
				end
			end
		end
	end

	if cache.encounterID then EJ_SelectEncounter(cache.encounterID) end
	if cache.classID and cache.specID then EJ_SetLootFilter(cache.classID, cache.specID) end

	for _, itemCache in pairs(cache.items) do
		local count = 0
		for _ in pairs(itemCache.specs) do
			count = count + 1
		end
		itemCache.everyone = count == numSpecs
	end
end

local function UpdateItem(button, pool)
	local specs = GetSpecsForItem(button)
	if specs == nil then return end

	if specs == true then specs = fakeEveryoneSpec end

	local config = GetConfig()
	local anchorKey = ANCHOR[config.anchor] or ANCHOR[1]
	local anchorFlip = ANCHORFLIP[anchorKey]
	local paddingFlip = PADDINGFLIP[anchorKey] or 1
	local spacing = config.spacing * paddingFlip
	local xPrevOffset = (1 * paddingFlip) - spacing
	local xOffset = config.offsetX * paddingFlip
	local yOffset = (-6 * paddingFlip * (PADDINGFLIP[anchorFlip] or 1)) + (config.offsetY * paddingFlip)
	local iconPadding = ClampValue(type(config.iconPadding) == "number" and config.iconPadding or 0, 0, 0.5)

	local previousTexture
	for _, info in ipairs(specs) do
		local texture = pool:Acquire()
		texture:SetSize(16, 16)
		texture:SetScale(config.textureScale or 1)
		texture:ClearAllPoints()
		if previousTexture then
			texture:SetPoint(anchorKey, previousTexture, anchorFlip, xPrevOffset, 0)
		else
			texture:SetPoint(anchorKey, button, anchorKey, xOffset, yOffset)
		end

		if info.specRole == true then
			texture:SetAtlas(ROLES_ATLAS[info.specName] or "")
			texture:SetTexCoord(iconPadding, 1 - iconPadding, iconPadding, 1 - iconPadding)
		elseif info.specIcon == true then
			texture:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
			local coords = CLASS_ICON_TCOORDS[info.classFile]
			if coords then
				texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
			else
				texture:SetTexCoord(0, 1, 0, 1)
			end
		else
			texture:SetTexture(info.specIcon or 134400)
			texture:SetTexCoord(iconPadding, 1 - iconPadding, iconPadding, 1 - iconPadding)
		end

		texture:Show()
		previousTexture = texture
	end
end

local function EnsurePool()
	if not EncounterJournal or not EncounterJournal.encounter or not EncounterJournal.encounter.info then return end
	local lootContainer = EncounterJournal.encounter.info.LootContainer
	if not lootContainer or not lootContainer.ScrollBox then return end

	if not Module.pool then Module.pool = CreateTexturePool(lootContainer.ScrollBox, "OVERLAY", 7) end
	Module.scrollBox = lootContainer.ScrollBox
end

function Module:UpdateLoot()
	if not self.enabled then
		if self.pool then self.pool:ReleaseAll() end
		return
	end

	if not self.pool or not self.scrollBox then EnsurePool() end
	if not self.pool or not self.scrollBox then return end

	self.pool:ReleaseAll()

	local buttons = self.scrollBox:GetFrames()
	if not buttons then return end

	local hasUpdatedItems
	for _, button in ipairs(buttons) do
		if button:IsShown() and button:IsVisible() then
			if not hasUpdatedItems then
				hasUpdatedItems = true
				UpdateItems()
			end
			UpdateItem(button, self.pool)
		end
	end
end

function Module:Refresh()
	if self.enabled then self:UpdateLoot() end
end

local function ScrollBoxUpdate()
	Module:UpdateLoot()
end

function Module:TryLoad()
	if not self.enabled then return end
	if not EncounterJournal or not EncounterJournal.encounter then return end

	EnsurePool()
	if not self.pool or not self.scrollBox then return end

	if not self.hookedLootUpdate then
		hooksecurefunc("EncounterJournal_LootUpdate", function()
			Module:UpdateLoot()
		end)
		self.hookedLootUpdate = true
	end

	if not self.scrollCallback then self.scrollCallback = ScrollBoxUpdate end
	if not self.scrollCallbackRegistered then
		self.scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnUpdate, self.scrollCallback)
		self.scrollCallbackRegistered = true
	end

	self:UpdateLoot()
end

function Module:OnEvent(event, arg1)
	if not self.enabled then return end

	if event == "ADDON_LOADED" and arg1 == "Blizzard_EncounterJournal" then
		self:TryLoad()
	elseif event == "PLAYER_ENTERING_WORLD" then
		BuildClassData()
		wipe(cache.items)
		self:UpdateLoot()
	elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
		if arg1 == nil or arg1 == "player" then
			BuildClassData()
			wipe(cache.items)
			self:UpdateLoot()
		end
	end
end

Module.frame:SetScript("OnEvent", function(_, event, arg1)
	Module:OnEvent(event, arg1)
end)

function Module:SetEnabled(value)
	value = not not value
	if value == self.enabled then
		if value then self:Refresh() end
		return
	end

	self.enabled = value

	if value then
		BuildClassData()
		wipe(cache.items)
		cache.difficulty = nil
		cache.instanceID = nil
		cache.encounterID = nil
		cache.classID = nil
		cache.specID = nil
		self.frame:RegisterEvent("ADDON_LOADED")
		self.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
		self.frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		self:TryLoad()
	else
		self.frame:UnregisterEvent("ADDON_LOADED")
		self.frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
		self.frame:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		if self.pool then self.pool:ReleaseAll() end
		if self.scrollBox and self.scrollCallbackRegistered and self.scrollCallback then
			self.scrollBox:UnregisterCallback(ScrollBoxListMixin.Event.OnUpdate, self.scrollCallback)
			self.scrollCallbackRegistered = false
		end
	end
end
