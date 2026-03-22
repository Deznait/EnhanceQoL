-- luacheck: globals MinimapCluster C_DelvesUI
local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local InstanceDifficulty = addon.InstanceDifficulty or {}
addon.InstanceDifficulty = InstanceDifficulty
InstanceDifficulty.enabled = InstanceDifficulty.enabled or false

InstanceDifficulty.frame = InstanceDifficulty.frame or CreateFrame("Frame")

local function getIndicator() return MinimapCluster and MinimapCluster.InstanceDifficulty end

local function defaultFontFace()
	if addon.functions and addon.functions.GetGlobalDefaultFontFace then return addon.functions.GetGlobalDefaultFontFace() end
	return (addon.variables and addon.variables.defaultFont) or STANDARD_TEXT_FONT
end

function InstanceDifficulty:EnsureText()
	local indicator = getIndicator()
	if not indicator then return nil end
	if not self.text or self.text:GetParent() ~= indicator then
		self.text = indicator:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		self.text:Hide()
	end
	return self.text
end

function InstanceDifficulty:ApplyTextStyle()
	if not self:EnsureText() then return end
	local fontSize = (addon.db and addon.db["instanceDifficultyFontSize"]) or 14
	local font = defaultFontFace()
	local ok = self.text:SetFont(font, fontSize, "OUTLINE")
	if ok == false then self.text:SetFont((addon.variables and addon.variables.defaultFont) or STANDARD_TEXT_FONT, fontSize, "OUTLINE") end
end

local nmNames = {
	[RAID_DIFFICULTY1] = true,
	[RAID_DIFFICULTY2] = true,
	[RAID_DIFFICULTY_10PLAYER] = true,
	[RAID_DIFFICULTY_20PLAYER] = true,
	[RAID_DIFFICULTY_25PLAYER] = true,
	[RAID_DIFFICULTY_40PLAYER] = true,
}

local hcNames = {
	[RAID_DIFFICULTY3] = true,
	[RAID_DIFFICULTY4] = true,
	[RAID_DIFFICULTY_10PLAYER_HEROIC] = true,
	[RAID_DIFFICULTY_25PLAYER_HEROIC] = true,
}

local function getActiveDelveTier()
	if not C_DelvesUI or not C_GossipInfo then return nil end

	local _, _, _, mapID = UnitPosition("player")
	if not C_DelvesUI.HasActiveDelve(mapID) then return nil end

	local gossipInfo = C_GossipInfo.GetActiveDelveGossip()
	local orderIndex = gossipInfo and gossipInfo.orderIndex
	if type(orderIndex) == "number" and orderIndex >= 0 then return orderIndex + 1 end

	return nil
end

local function getShortLabel(difficultyID, difficultyName)
	if difficultyID == 1 or difficultyID == 3 or difficultyID == 4 or difficultyID == 14 or difficultyID == 33 or difficultyID == 150 or nmNames[difficultyName] or difficultyID == 12 then
		return "NM"
	elseif difficultyID == 2 or difficultyID == 5 or difficultyID == 6 or difficultyID == 15 or difficultyID == 205 or difficultyID == 230 or hcNames[difficultyName] or difficultyID == 13 then
		return "HC"
	elseif difficultyID == 16 or difficultyID == 23 then
		return "M"
	elseif difficultyID == 8 then
		local level = C_ChallengeMode.GetActiveKeystoneInfo()
		if level and type(level) == "number" and level > 0 then return "M+" .. level end
		return "M+"
	elseif difficultyID == 7 or difficultyID == 17 or difficultyID == 151 then
		return "LFR"
	elseif difficultyID == 24 then
		return "TW"
	elseif difficultyID == 208 then
		local tier = getActiveDelveTier()
		if tier then return "D" .. tier end
		return "D"
	end
	return difficultyName
end

function InstanceDifficulty:Update()
	local indicator = getIndicator()
	if not self.enabled or not addon.db or not indicator then return end
	if not self:EnsureText() then return end
	if not IsInInstance() then
		self.text:Hide()
		return
	end

	local _, _, difficultyID, difficultyName, _, _, _, _, maxPlayers = GetInstanceInfo()
	local short = getShortLabel(difficultyID, difficultyName)
	-- Stable code for color mapping
	local code
	if difficultyID == 1 or difficultyID == 3 or difficultyID == 4 or difficultyID == 14 or difficultyID == 33 or difficultyID == 150 or nmNames[difficultyName] then
		code = "NM"
	elseif difficultyID == 2 or difficultyID == 5 or difficultyID == 6 or difficultyID == 15 or difficultyID == 205 or difficultyID == 230 or hcNames[difficultyName] then
		code = "HC"
	elseif difficultyID == 16 or difficultyID == 23 then
		code = "M"
	elseif difficultyID == 8 then
		code = "MPLUS"
	elseif difficultyID == 7 or difficultyID == 17 or difficultyID == 151 then
		code = "LFR"
	elseif difficultyID == 24 then
		code = "TW"
	end

	local text
	if maxPlayers and maxPlayers > 0 then
		text = string.format("%d (%s)", maxPlayers, short)
	else
		text = short
	end
	-- Apply anchor (fixed center) and offsets
	local anchor = "CENTER"
	local offX = (addon.db and addon.db["instanceDifficultyOffsetX"]) or 0
	local offY = (addon.db and addon.db["instanceDifficultyOffsetY"]) or 0
	self.text:ClearAllPoints()
	self.text:SetPoint(anchor, indicator, anchor, offX, offY)

	self.text:SetText(text)
	self:ApplyTextStyle()
	-- Apply optional difficulty colors
	if addon.db and addon.db["instanceDifficultyUseColors"] then
		local colors = addon.db["instanceDifficultyColors"] or {}
		local c = (code and colors[code]) or { r = 1, g = 1, b = 1 }
		self.text:SetTextColor(c.r or 1, c.g or 1, c.b or 1)
	else
		self.text:SetTextColor(1, 1, 1)
	end
	self.text:Show()
end

function InstanceDifficulty:ApplyIndicatorOverride(enabled)
	local indicator = getIndicator()
	if not indicator then return end
	indicator:SetAlpha(1)
	for _, key in ipairs({ "Default", "ChallengeMode", "Guild" }) do
		local child = indicator[key]
		if child then
			if enabled then
				child:Hide()
				child:SetScript("OnShow", child.Hide)
			else
				if child:GetScript("OnShow") == child.Hide then child:SetScript("OnShow", nil) end
			end
		end
	end
	if enabled and not self._indicatorOnShowHooked then
		self._indicatorOnShowHooked = true
		indicator:HookScript("OnShow", function() InstanceDifficulty:Update() end)
	end
end

function InstanceDifficulty:SetEnabled(value)
	self.enabled = value
	if value then
		self:ApplyIndicatorOverride(true)
		self:EnsureText()
		self.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
		self.frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
		self.frame:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
		self.frame:RegisterEvent("CHALLENGE_MODE_START")
		self.frame:RegisterEvent("ACTIVE_DELVE_DATA_UPDATE")
		self:Update()
	else
		self.frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
		self.frame:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
		self.frame:UnregisterEvent("PLAYER_DIFFICULTY_CHANGED")
		self.frame:UnregisterEvent("CHALLENGE_MODE_START")
		self.frame:UnregisterEvent("ACTIVE_DELVE_DATA_UPDATE")
		if self.text then self.text:Hide() end
		self:ApplyIndicatorOverride(false)
		local indicator = getIndicator()
		if indicator then
			indicator:Show()
			local miniMapInstanceDifficultyUpdate = _G.MiniMapInstanceDifficulty_Update
			if miniMapInstanceDifficultyUpdate then
				pcall(miniMapInstanceDifficultyUpdate)
			elseif indicator.Default then
				indicator.Default:Show()
			elseif indicator.ChallengeMode then
				indicator.ChallengeMode:Show()
			elseif indicator.Guild then
				indicator.Guild:Show()
			end
		end
	end
end

InstanceDifficulty.frame:SetScript("OnEvent", function(e) InstanceDifficulty:Update() end)
