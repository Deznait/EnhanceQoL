local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.Aura = addon.Aura or {}
addon.Aura.TotalAbsorbTracker = addon.Aura.TotalAbsorbTracker or {}
local Tracker = addon.Aura.TotalAbsorbTracker

local L = LibStub("AceLocale-3.0"):GetLocale(parentAddonName)
local EditMode = addon.EditMode
local SettingType = EditMode and EditMode.lib and EditMode.lib.SettingType
local LSM = LibStub("LibSharedMedia-3.0", true)

local UIParent = _G.UIParent
local CreateUnitHealPredictionCalculator = _G.CreateUnitHealPredictionCalculator
local UnitGetDetailedHealPrediction = _G.UnitGetDetailedHealPrediction
local UnitExists = _G.UnitExists
local AbbreviateNumbers = _G.AbbreviateNumbers
local STANDARD_TEXT_FONT = _G.STANDARD_TEXT_FONT
local NONE = _G.NONE or "None"
local DEFAULT = _G.DEFAULT or "Default"
local Enum = _G.Enum

local EDITMODE_ID = "totalAbsorbTracker"
local DEFAULT_SETTINGS_MAX_HEIGHT = 900
local PREVIEW_AMOUNT = 123456
local ANCHOR_POINTS = {
	"TOPLEFT",
	"TOP",
	"TOPRIGHT",
	"LEFT",
	"CENTER",
	"RIGHT",
	"BOTTOMLEFT",
	"BOTTOM",
	"BOTTOMRIGHT",
}
local OUTLINE_OPTIONS = {
	"NONE",
	"OUTLINE",
	"THICKOUTLINE",
	"MONOCHROMEOUTLINE",
}
local DEFAULT_ICON_IDS = {
	135940,
	1769069,
	252184,
}

Tracker.defaults = Tracker.defaults
	or {
		point = "CENTER",
		relativePoint = "CENTER",
		x = 0,
		y = -80,
		iconSize = 44,
		icon = 135940,
		iconOffsetX = 0,
		iconOffsetY = 0,
		borderEnabled = false,
		borderTexture = "DEFAULT",
		borderSize = 1,
		borderOffset = 0,
		borderColor = { 1, 1, 1, 1 },
		textFont = addon.functions and addon.functions.GetGlobalFontConfigKey and addon.functions.GetGlobalFontConfigKey() or "__EQOL_GLOBAL_FONT__",
		textSize = 18,
		textOutline = "OUTLINE",
		textColor = { 1, 1, 1, 1 },
		textAnchor = "CENTER",
		textOffsetX = 0,
		textOffsetY = 0,
		abbreviateNumbers = false,
	}

local defaults = Tracker.defaults
Tracker.currentAmount = Tracker.currentAmount or 0

local DB_ENABLED = "totalAbsorbTrackerEnabled"
local DB_POINT = "totalAbsorbTrackerPoint"
local DB_RELATIVE_POINT = "totalAbsorbTrackerRelativePoint"
local DB_X = "totalAbsorbTrackerX"
local DB_Y = "totalAbsorbTrackerY"
local DB_ICON_SIZE = "totalAbsorbTrackerIconSize"
local DB_ICON = "totalAbsorbTrackerIcon"
local DB_ICON_OFFSET_X = "totalAbsorbTrackerIconOffsetX"
local DB_ICON_OFFSET_Y = "totalAbsorbTrackerIconOffsetY"
local DB_BORDER_ENABLED = "totalAbsorbTrackerBorderEnabled"
local DB_BORDER_TEXTURE = "totalAbsorbTrackerBorderTexture"
local DB_BORDER_SIZE = "totalAbsorbTrackerBorderSize"
local DB_BORDER_OFFSET = "totalAbsorbTrackerBorderOffset"
local DB_BORDER_COLOR = "totalAbsorbTrackerBorderColor"
local DB_TEXT_FONT = "totalAbsorbTrackerTextFont"
local DB_TEXT_SIZE = "totalAbsorbTrackerTextSize"
local DB_TEXT_OUTLINE = "totalAbsorbTrackerTextOutline"
local DB_TEXT_COLOR = "totalAbsorbTrackerTextColor"
local DB_TEXT_ANCHOR = "totalAbsorbTrackerTextAnchor"
local DB_TEXT_OFFSET_X = "totalAbsorbTrackerTextOffsetX"
local DB_TEXT_OFFSET_Y = "totalAbsorbTrackerTextOffsetY"
local DB_ABBREVIATE = "totalAbsorbTrackerAbbreviateNumbers"

local frame
local eventFrame
local editModeRegistered = false

local function getDBValue(key, fallback)
	if addon.db and addon.db[key] ~= nil then return addon.db[key] end
	return fallback
end

local function copyColor(value, fallback)
	local color = value
	if type(color) ~= "table" then color = fallback or defaults.textColor end
	return {
		color.r or color[1] or 1,
		color.g or color[2] or 1,
		color.b or color[3] or 1,
		color.a or color[4] or 1,
	}
end

local function getFontOptions()
	local options = {}
	local globalKey = addon.functions and addon.functions.GetGlobalFontConfigKey and addon.functions.GetGlobalFontConfigKey() or defaults.textFont
	local globalLabel = addon.functions and addon.functions.GetGlobalFontConfigLabel and addon.functions.GetGlobalFontConfigLabel() or "Use global font config"
	options[#options + 1] = {
		value = globalKey,
		label = globalLabel,
	}

	local mediaOptions = addon.functions and addon.functions.GetLSMMediaOptions and addon.functions.GetLSMMediaOptions("font") or {}
	for i = 1, #mediaOptions do
		options[#options + 1] = {
			value = mediaOptions[i].value,
			label = mediaOptions[i].label,
		}
	end

	return options
end

local function getBorderOptions()
	local options = {
		{ value = "DEFAULT", label = DEFAULT },
		{ value = "SOLID", label = "Solid" },
	}
	local mediaOptions = addon.functions and addon.functions.GetLSMMediaOptions and addon.functions.GetLSMMediaOptions("border") or {}
	for i = 1, #mediaOptions do
		options[#options + 1] = {
			value = mediaOptions[i].value,
			label = mediaOptions[i].label,
		}
	end
	return options
end

local function isLikelyFilePath(value)
	if type(value) ~= "string" or value == "" then return false end
	return value:find("/", 1, true) ~= nil or value:find("\\", 1, true) ~= nil
end

local function resolveBorderTexture(value)
	if value == "SOLID" then return "Interface\\Buttons\\WHITE8x8" end
	if not value or value == "" or value == "DEFAULT" then return "Interface\\Buttons\\WHITE8x8" end
	if LSM and LSM.Fetch then
		local texture = LSM:Fetch("border", value, true)
		if texture then return texture end
	end
	if isLikelyFilePath(value) then return value end
	return "Interface\\Buttons\\WHITE8x8"
end

function Tracker:IsEnabled() return addon.db and addon.db[DB_ENABLED] == true end

function Tracker:GetPoint() return getDBValue(DB_POINT, defaults.point) end

function Tracker:GetRelativePoint() return getDBValue(DB_RELATIVE_POINT, getDBValue(DB_POINT, defaults.relativePoint or defaults.point)) end

function Tracker:GetOffsetX() return getDBValue(DB_X, defaults.x) end

function Tracker:GetOffsetY() return getDBValue(DB_Y, defaults.y) end

function Tracker:GetIconSize() return getDBValue(DB_ICON_SIZE, defaults.iconSize) end

function Tracker:GetIconTexture() return getDBValue(DB_ICON, defaults.icon) end

function Tracker:GetIconOffsetX() return getDBValue(DB_ICON_OFFSET_X, defaults.iconOffsetX) end

function Tracker:GetIconOffsetY() return getDBValue(DB_ICON_OFFSET_Y, defaults.iconOffsetY) end

function Tracker:GetBorderEnabled() return getDBValue(DB_BORDER_ENABLED, defaults.borderEnabled) == true end

function Tracker:GetBorderTextureKey() return getDBValue(DB_BORDER_TEXTURE, defaults.borderTexture) end

function Tracker:GetBorderSize() return getDBValue(DB_BORDER_SIZE, defaults.borderSize) end

function Tracker:GetBorderOffset() return getDBValue(DB_BORDER_OFFSET, defaults.borderOffset) end

function Tracker:GetBorderColor() return copyColor(getDBValue(DB_BORDER_COLOR, defaults.borderColor), defaults.borderColor) end

function Tracker:GetTextFontKey() return getDBValue(DB_TEXT_FONT, defaults.textFont) end

function Tracker:GetTextSize() return getDBValue(DB_TEXT_SIZE, defaults.textSize) end

function Tracker:GetTextOutline() return getDBValue(DB_TEXT_OUTLINE, defaults.textOutline) end

function Tracker:GetTextColor() return copyColor(getDBValue(DB_TEXT_COLOR, defaults.textColor), defaults.textColor) end

function Tracker:GetTextAnchor() return getDBValue(DB_TEXT_ANCHOR, defaults.textAnchor) end

function Tracker:GetTextOffsetX() return getDBValue(DB_TEXT_OFFSET_X, defaults.textOffsetX) end

function Tracker:GetTextOffsetY() return getDBValue(DB_TEXT_OFFSET_Y, defaults.textOffsetY) end

function Tracker:GetAbbreviateNumbers() return getDBValue(DB_ABBREVIATE, defaults.abbreviateNumbers) == true end

function Tracker:ResolveTextFont()
	local fallback = (addon.functions and addon.functions.GetLocaleDefaultFontFace and addon.functions.GetLocaleDefaultFontFace()) or addon.variables.defaultFont or STANDARD_TEXT_FONT
	if addon.functions and addon.functions.ResolveFontFace then return addon.functions.ResolveFontFace(self:GetTextFontKey(), fallback) end
	return fallback
end

function Tracker:EnsureCalculator()
	if self._calculatorUnsupported then return nil end
	if self._calculator then return self._calculator end
	if not (CreateUnitHealPredictionCalculator and UnitGetDetailedHealPrediction) then
		self._calculatorUnsupported = true
		return nil
	end

	local calculator = CreateUnitHealPredictionCalculator()
	if not calculator then
		self._calculatorUnsupported = true
		return nil
	end

	if calculator.SetDamageAbsorbClampMode and Enum and Enum.UnitDamageAbsorbClampMode then calculator:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MaximumHealth) end

	self._calculator = calculator
	return calculator
end

function Tracker:EvaluateAbsorbAmount()
	local calculator = self:EnsureCalculator()
	if calculator and UnitGetDetailedHealPrediction and UnitExists and UnitExists("player") then
		if calculator.ResetPredictedValues then calculator:ResetPredictedValues() end
		if calculator.SetDamageAbsorbClampMode and Enum and Enum.UnitDamageAbsorbClampMode then calculator:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MaximumHealth) end
		UnitGetDetailedHealPrediction("player", "player", calculator)
		if calculator.GetDamageAbsorbs then return calculator:GetDamageAbsorbs() end
	end

	local fallback = _G.UnitGetTotalAbsorbs and _G.UnitGetTotalAbsorbs("player") or 0
	return fallback, false
end

function Tracker:FormatAmount(value)
	if self:GetAbbreviateNumbers() and AbbreviateNumbers then return AbbreviateNumbers(value) end
	return value
end

function Tracker:BuildLayoutRecordFromProfile()
	return {
		point = self:GetPoint(),
		relativePoint = self:GetRelativePoint(),
		x = self:GetOffsetX(),
		y = self:GetOffsetY(),
		iconSize = self:GetIconSize(),
		icon = self:GetIconTexture(),
		iconOffsetX = self:GetIconOffsetX(),
		iconOffsetY = self:GetIconOffsetY(),
		borderEnabled = self:GetBorderEnabled(),
		borderTexture = self:GetBorderTextureKey(),
		borderSize = self:GetBorderSize(),
		borderOffset = self:GetBorderOffset(),
		borderColor = copyColor(self:GetBorderColor(), defaults.borderColor),
		textFont = self:GetTextFontKey(),
		textSize = self:GetTextSize(),
		textOutline = self:GetTextOutline(),
		textColor = copyColor(self:GetTextColor(), defaults.textColor),
		textAnchor = self:GetTextAnchor(),
		textOffsetX = self:GetTextOffsetX(),
		textOffsetY = self:GetTextOffsetY(),
		abbreviateNumbers = self:GetAbbreviateNumbers(),
	}
end

local function seedEditModeRecordFromProfile(record)
	if type(record) ~= "table" then return end
	local source = Tracker:BuildLayoutRecordFromProfile()
	for key, value in pairs(source) do
		record[key] = value
	end
end

function Tracker:ApplyLayoutData(data)
	local record = type(data) == "table" and data or {}
	local point = record.point
	if point == nil then point = self:GetPoint() end
	local relativePoint = record.relativePoint
	if relativePoint == nil then relativePoint = self:GetRelativePoint() end
	local x = record.x
	if x == nil then x = self:GetOffsetX() end
	local y = record.y
	if y == nil then y = self:GetOffsetY() end
	local iconSize = record.iconSize
	if iconSize == nil then iconSize = self:GetIconSize() end
	local icon = record.icon
	if icon == nil then icon = self:GetIconTexture() end
	local iconOffsetX = record.iconOffsetX
	if iconOffsetX == nil then iconOffsetX = self:GetIconOffsetX() end
	local iconOffsetY = record.iconOffsetY
	if iconOffsetY == nil then iconOffsetY = self:GetIconOffsetY() end
	local borderEnabled = record.borderEnabled
	if borderEnabled == nil then borderEnabled = self:GetBorderEnabled() end
	local borderTexture = record.borderTexture
	if borderTexture == nil then borderTexture = self:GetBorderTextureKey() end
	local borderSize = record.borderSize
	if borderSize == nil then borderSize = self:GetBorderSize() end
	local borderOffset = record.borderOffset
	if borderOffset == nil then borderOffset = self:GetBorderOffset() end
	local borderColor = record.borderColor
	if borderColor == nil then borderColor = self:GetBorderColor() end
	local textFont = record.textFont
	if textFont == nil then textFont = self:GetTextFontKey() end
	local textSize = record.textSize
	if textSize == nil then textSize = self:GetTextSize() end
	local textOutline = record.textOutline
	if textOutline == nil then textOutline = self:GetTextOutline() end
	local textColor = record.textColor
	if textColor == nil then textColor = self:GetTextColor() end
	local textAnchor = record.textAnchor
	if textAnchor == nil then textAnchor = self:GetTextAnchor() end
	local textOffsetX = record.textOffsetX
	if textOffsetX == nil then textOffsetX = self:GetTextOffsetX() end
	local textOffsetY = record.textOffsetY
	if textOffsetY == nil then textOffsetY = self:GetTextOffsetY() end
	local abbreviateNumbers = record.abbreviateNumbers
	if abbreviateNumbers == nil then abbreviateNumbers = self:GetAbbreviateNumbers() end

	addon.db = addon.db or {}
	addon.db[DB_POINT] = point
	addon.db[DB_RELATIVE_POINT] = relativePoint
	addon.db[DB_X] = x
	addon.db[DB_Y] = y
	addon.db[DB_ICON_SIZE] = iconSize
	addon.db[DB_ICON] = icon
	addon.db[DB_ICON_OFFSET_X] = iconOffsetX
	addon.db[DB_ICON_OFFSET_Y] = iconOffsetY
	addon.db[DB_BORDER_ENABLED] = borderEnabled == true
	addon.db[DB_BORDER_TEXTURE] = borderTexture
	addon.db[DB_BORDER_SIZE] = borderSize
	addon.db[DB_BORDER_OFFSET] = borderOffset
	addon.db[DB_BORDER_COLOR] = borderColor
	addon.db[DB_TEXT_FONT] = textFont
	addon.db[DB_TEXT_SIZE] = textSize
	addon.db[DB_TEXT_OUTLINE] = textOutline
	addon.db[DB_TEXT_COLOR] = textColor
	addon.db[DB_TEXT_ANCHOR] = textAnchor
	addon.db[DB_TEXT_OFFSET_X] = textOffsetX
	addon.db[DB_TEXT_OFFSET_Y] = textOffsetY
	addon.db[DB_ABBREVIATE] = abbreviateNumbers == true

	if not frame then return end

	frame:SetSize(iconSize, iconSize)
	frame:ClearAllPoints()
	frame:SetPoint(point, UIParent, relativePoint or point, x or 0, y or 0)

	frame.icon:ClearAllPoints()
	frame.icon:SetPoint("CENTER", frame, "CENTER", iconOffsetX or 0, iconOffsetY or 0)
	frame.icon:SetSize(iconSize, iconSize)
	frame.icon:SetTexture(icon)

	if frame.border then
		if not borderEnabled then
			frame.border:SetBackdrop(nil)
			frame.border:Hide()
		else
			frame.border:SetBackdrop({
				edgeFile = resolveBorderTexture(borderTexture),
				edgeSize = borderSize,
				insets = { left = 0, right = 0, top = 0, bottom = 0 },
			})
			local borderColorValue = copyColor(borderColor, defaults.borderColor)
			frame.border:SetBackdropBorderColor(borderColorValue[1], borderColorValue[2], borderColorValue[3], borderColorValue[4])
			frame.border:SetBackdropColor(0, 0, 0, 0)
			frame.border:ClearAllPoints()
			frame.border:SetPoint("TOPLEFT", frame.icon, "TOPLEFT", -(borderOffset or 0), borderOffset or 0)
			frame.border:SetPoint("BOTTOMRIGHT", frame.icon, "BOTTOMRIGHT", borderOffset or 0, -(borderOffset or 0))
			frame.border:Show()
		end
	end

	local fontPath = self:ResolveTextFont()
	local fontOutline = textOutline == "NONE" and "" or textOutline
	local ok = frame.text:SetFont(fontPath, textSize, fontOutline)
	if ok == false then
		local fallback = addon.variables.defaultFont or STANDARD_TEXT_FONT
		frame.text:SetFont(fallback, textSize, fontOutline)
	end
	local color = copyColor(textColor, defaults.textColor)
	frame.text:SetTextColor(color[1], color[2], color[3], color[4])
	frame.text:ClearAllPoints()
	frame.text:SetPoint(textAnchor, frame.icon, textAnchor, textOffsetX or 0, textOffsetY or 0)

	if self.previewing then
		frame.icon:SetAlpha(PREVIEW_AMOUNT)
		if frame.border then frame.border:SetAlpha(PREVIEW_AMOUNT) end
		frame.text:SetAlpha(PREVIEW_AMOUNT)
		frame.text:SetText(self:FormatAmount(PREVIEW_AMOUNT))
	else
		frame.icon:SetAlpha(self.currentAmount)
		if frame.border then frame.border:SetAlpha(self.currentAmount) end
		frame.text:SetAlpha(self.currentAmount)
		frame.text:SetText(self:FormatAmount(self.currentAmount))
	end
end

function Tracker:EnsureFrame()
	if frame then return frame end

	frame = CreateFrame("Frame", "EQOLTotalAbsorbTracker", UIParent)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(false)

	frame.editBg = frame:CreateTexture(nil, "BACKGROUND")
	frame.editBg:SetAllPoints(frame)
	frame.editBg:SetColorTexture(0, 0, 0, 0.45)
	frame.editBg:Hide()

	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetPoint("CENTER", frame, "CENTER", 0, 0)

	frame.border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	frame.border:SetFrameLevel((frame:GetFrameLevel() or 0) + 4)
	frame.border:SetFrameStrata(frame:GetFrameStrata())
	frame.border:Hide()

	frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
	frame.text:SetJustifyH("CENTER")
	frame.text:SetJustifyV("MIDDLE")

	frame.editLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.editLabel:SetPoint("CENTER", frame, "CENTER", 0, 0)
	frame.editLabel:SetText(L["TotalAbsorbTracker"] or "Total Absorb Tracker")
	frame.editLabel:Hide()

	self:ApplyLayoutData(self:BuildLayoutRecordFromProfile())
	return frame
end

function Tracker:ShowEditModeHint(show)
	local trackerFrame = self:EnsureFrame()
	self.previewing = show == true
	if self.previewing then
		trackerFrame.editBg:Show()
		trackerFrame.editLabel:Show()
		trackerFrame:Show()
		trackerFrame.icon:SetAlpha(PREVIEW_AMOUNT)
		if trackerFrame.border then trackerFrame.border:SetAlpha(PREVIEW_AMOUNT) end
		trackerFrame.text:SetAlpha(PREVIEW_AMOUNT)
		trackerFrame.text:SetText(self:FormatAmount(PREVIEW_AMOUNT))
		return
	end

	trackerFrame.editBg:Hide()
	trackerFrame.editLabel:Hide()
	self:Refresh()
end

function Tracker:RefreshAppearance()
	if not frame then return end
	self:ApplyLayoutData(self:BuildLayoutRecordFromProfile())
	if self.previewing then
		frame.icon:SetAlpha(PREVIEW_AMOUNT)
		if frame.border then frame.border:SetAlpha(PREVIEW_AMOUNT) end
		frame.text:SetAlpha(PREVIEW_AMOUNT)
		frame.text:SetText(self:FormatAmount(PREVIEW_AMOUNT))
	else
		frame.icon:SetAlpha(self.currentAmount)
		if frame.border then frame.border:SetAlpha(self.currentAmount) end
		frame.text:SetAlpha(self.currentAmount)
		frame.text:SetText(self:FormatAmount(self.currentAmount))
	end
end

function Tracker:Refresh()
	if not self:IsEnabled() then
		if frame then frame:Hide() end
		return
	end

	local trackerFrame = self:EnsureFrame()
	self:ApplyLayoutData(self:BuildLayoutRecordFromProfile())

	if self.previewing then
		trackerFrame:Show()
		trackerFrame.icon:SetAlpha(PREVIEW_AMOUNT)
		if trackerFrame.border then trackerFrame.border:SetAlpha(PREVIEW_AMOUNT) end
		trackerFrame.text:SetAlpha(PREVIEW_AMOUNT)
		trackerFrame.text:SetText(self:FormatAmount(PREVIEW_AMOUNT))
		return
	end

	local amount = self:EvaluateAbsorbAmount()
	self.currentAmount = amount
	trackerFrame.icon:SetAlpha(amount)
	if trackerFrame.border then trackerFrame.border:SetAlpha(amount) end
	trackerFrame.text:SetAlpha(amount)
	trackerFrame.text:SetText(self:FormatAmount(amount))
	trackerFrame:Show()
end

function Tracker:EnsureEventFrame()
	if eventFrame then return eventFrame end
	eventFrame = CreateFrame("Frame")
	eventFrame:SetScript("OnEvent", function(_, event, unit)
		if event == "PLAYER_ENTERING_WORLD" then
			Tracker:Refresh()
			return
		end
		if unit ~= "player" then return end
		Tracker:Refresh()
	end)
	return eventFrame
end

function Tracker:RegisterEvents()
	local watcher = self:EnsureEventFrame()
	watcher:UnregisterAllEvents()
	watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	watcher:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player")
	watcher:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
	watcher:RegisterUnitEvent("UNIT_MAX_HEALTH_MODIFIERS_CHANGED", "player")
end

function Tracker:UnregisterEvents()
	if not eventFrame then return end
	eventFrame:UnregisterAllEvents()
end

function Tracker:RegisterEditMode()
	if editModeRegistered or not EditMode or not EditMode.RegisterFrame then return end
	local trackerFrame = self:EnsureFrame()

	local settings
	if SettingType then
		settings = {
			{
				name = L["Icon"] or "Icon",
				kind = SettingType.Collapsible,
				id = "totalAbsorbTrackerIcon",
				defaultCollapsed = false,
			},
			{
				name = L["Tracker icon"] or "Tracker icon",
				kind = SettingType.Dropdown,
				field = "icon",
				parentId = "totalAbsorbTrackerIcon",
				height = 180,
				get = function() return Tracker:GetIconTexture() end,
				set = function(_, value) Tracker:ApplyLayoutData({ icon = value }) end,
				generator = function(_, root)
					for i = 1, #DEFAULT_ICON_IDS do
						local iconId = DEFAULT_ICON_IDS[i]
						local label = string.format("|T%d:16|t %d", iconId, iconId)
						root:CreateRadio(label, function() return Tracker:GetIconTexture() == iconId end, function() Tracker:ApplyLayoutData({ icon = iconId }) end)
					end
				end,
			},
			{
				name = L["Icon size"] or "Icon size",
				kind = SettingType.Slider,
				field = "iconSize",
				parentId = "totalAbsorbTrackerIcon",
				minValue = 8,
				maxValue = 128,
				valueStep = 1,
				allowInput = true,
				get = function() return Tracker:GetIconSize() end,
				set = function(_, value) Tracker:ApplyLayoutData({ iconSize = value }) end,
			},
			{
				name = L["Icon X offset"] or "Icon X offset",
				kind = SettingType.Slider,
				field = "iconOffsetX",
				parentId = "totalAbsorbTrackerIcon",
				minValue = -200,
				maxValue = 200,
				valueStep = 1,
				allowInput = true,
				get = function() return Tracker:GetIconOffsetX() end,
				set = function(_, value) Tracker:ApplyLayoutData({ iconOffsetX = value }) end,
			},
			{
				name = L["Icon Y offset"] or "Icon Y offset",
				kind = SettingType.Slider,
				field = "iconOffsetY",
				parentId = "totalAbsorbTrackerIcon",
				minValue = -200,
				maxValue = 200,
				valueStep = 1,
				allowInput = true,
				get = function() return Tracker:GetIconOffsetY() end,
				set = function(_, value) Tracker:ApplyLayoutData({ iconOffsetY = value }) end,
			},
			{
				name = L["Border"] or "Border",
				kind = SettingType.Collapsible,
				id = "totalAbsorbTrackerBorder",
				defaultCollapsed = true,
			},
			{
				name = L["Use border"] or "Use border",
				kind = SettingType.Checkbox,
				field = "borderEnabled",
				parentId = "totalAbsorbTrackerBorder",
				get = function() return Tracker:GetBorderEnabled() end,
				set = function(_, value) Tracker:ApplyLayoutData({ borderEnabled = value == true }) end,
			},
			{
				name = L["Border texture"] or "Border texture",
				kind = SettingType.Dropdown,
				field = "borderTexture",
				parentId = "totalAbsorbTrackerBorder",
				height = 180,
				get = function() return Tracker:GetBorderTextureKey() end,
				set = function(_, value) Tracker:ApplyLayoutData({ borderTexture = value }) end,
				generator = function(_, root)
					local options = getBorderOptions()
					for i = 1, #options do
						local option = options[i]
						root:CreateRadio(option.label, function() return Tracker:GetBorderTextureKey() == option.value end, function() Tracker:ApplyLayoutData({ borderTexture = option.value }) end)
					end
				end,
				isEnabled = function() return Tracker:GetBorderEnabled() end,
			},
			{
				name = L["Border size"] or "Border size",
				kind = SettingType.Slider,
				field = "borderSize",
				parentId = "totalAbsorbTrackerBorder",
				minValue = 1,
				maxValue = 32,
				valueStep = 1,
				allowInput = true,
				get = function() return Tracker:GetBorderSize() end,
				set = function(_, value) Tracker:ApplyLayoutData({ borderSize = value }) end,
				isEnabled = function() return Tracker:GetBorderEnabled() end,
			},
			{
				name = L["Border offset"] or "Border offset",
				kind = SettingType.Slider,
				field = "borderOffset",
				parentId = "totalAbsorbTrackerBorder",
				minValue = -20,
				maxValue = 20,
				valueStep = 1,
				allowInput = true,
				get = function() return Tracker:GetBorderOffset() end,
				set = function(_, value) Tracker:ApplyLayoutData({ borderOffset = value }) end,
				isEnabled = function() return Tracker:GetBorderEnabled() end,
			},
			{
				name = L["Border color"] or "Border color",
				kind = SettingType.Color,
				field = "borderColor",
				parentId = "totalAbsorbTrackerBorder",
				hasOpacity = true,
				get = function()
					local color = Tracker:GetBorderColor()
					return { r = color[1], g = color[2], b = color[3], a = color[4] }
				end,
				set = function(_, value) Tracker:ApplyLayoutData({ borderColor = value }) end,
				isEnabled = function() return Tracker:GetBorderEnabled() end,
			},
			{
				name = L["Text"] or "Text",
				kind = SettingType.Collapsible,
				id = "totalAbsorbTrackerText",
				defaultCollapsed = true,
			},
			{
				name = L["Use short numbers"] or "Use short numbers",
				kind = SettingType.Checkbox,
				field = "abbreviateNumbers",
				parentId = "totalAbsorbTrackerText",
				get = function() return Tracker:GetAbbreviateNumbers() end,
				set = function(_, value) Tracker:ApplyLayoutData({ abbreviateNumbers = value == true }) end,
			},
			{
				name = L["Text font"] or "Text font",
				kind = SettingType.Dropdown,
				field = "textFont",
				parentId = "totalAbsorbTrackerText",
				height = 180,
				get = function() return Tracker:GetTextFontKey() end,
				set = function(_, value) Tracker:ApplyLayoutData({ textFont = value }) end,
				generator = function(_, root)
					local options = getFontOptions()
					for i = 1, #options do
						local option = options[i]
						root:CreateRadio(option.label, function() return Tracker:GetTextFontKey() == option.value end, function() Tracker:ApplyLayoutData({ textFont = option.value }) end)
					end
				end,
			},
			{
				name = L["Text size"] or "Text size",
				kind = SettingType.Slider,
				field = "textSize",
				parentId = "totalAbsorbTrackerText",
				minValue = 8,
				maxValue = 72,
				valueStep = 1,
				allowInput = true,
				get = function() return Tracker:GetTextSize() end,
				set = function(_, value) Tracker:ApplyLayoutData({ textSize = value }) end,
			},
			{
				name = L["Font outline"] or "Font outline",
				kind = SettingType.Dropdown,
				field = "textOutline",
				parentId = "totalAbsorbTrackerText",
				height = 140,
				get = function() return Tracker:GetTextOutline() end,
				set = function(_, value) Tracker:ApplyLayoutData({ textOutline = value }) end,
				generator = function(_, root)
					for i = 1, #OUTLINE_OPTIONS do
						local value = OUTLINE_OPTIONS[i]
						local label = value == "NONE" and NONE or value
						root:CreateRadio(label, function() return Tracker:GetTextOutline() == value end, function() Tracker:ApplyLayoutData({ textOutline = value }) end)
					end
				end,
			},
			{
				name = L["Text color"] or "Text color",
				kind = SettingType.Color,
				field = "textColor",
				parentId = "totalAbsorbTrackerText",
				hasOpacity = true,
				get = function()
					local color = Tracker:GetTextColor()
					return { r = color[1], g = color[2], b = color[3], a = color[4] }
				end,
				set = function(_, value) Tracker:ApplyLayoutData({ textColor = value }) end,
			},
			{
				name = L["Text anchor"] or "Text anchor",
				kind = SettingType.Dropdown,
				field = "textAnchor",
				parentId = "totalAbsorbTrackerText",
				height = 180,
				get = function() return Tracker:GetTextAnchor() end,
				set = function(_, value) Tracker:ApplyLayoutData({ textAnchor = value }) end,
				generator = function(_, root)
					for i = 1, #ANCHOR_POINTS do
						local anchor = ANCHOR_POINTS[i]
						root:CreateRadio(anchor, function() return Tracker:GetTextAnchor() == anchor end, function() Tracker:ApplyLayoutData({ textAnchor = anchor }) end)
					end
				end,
			},
			{
				name = L["Text X offset"] or "Text X offset",
				kind = SettingType.Slider,
				field = "textOffsetX",
				parentId = "totalAbsorbTrackerText",
				minValue = -200,
				maxValue = 200,
				valueStep = 1,
				allowInput = true,
				get = function() return Tracker:GetTextOffsetX() end,
				set = function(_, value) Tracker:ApplyLayoutData({ textOffsetX = value }) end,
			},
			{
				name = L["Text Y offset"] or "Text Y offset",
				kind = SettingType.Slider,
				field = "textOffsetY",
				parentId = "totalAbsorbTrackerText",
				minValue = -200,
				maxValue = 200,
				valueStep = 1,
				allowInput = true,
				get = function() return Tracker:GetTextOffsetY() end,
				set = function(_, value) Tracker:ApplyLayoutData({ textOffsetY = value }) end,
			},
		}
	end

	EditMode:RegisterFrame(EDITMODE_ID, {
		frame = trackerFrame,
		title = L["TotalAbsorbTracker"] or "Total Absorb Tracker",
		layoutDefaults = self:BuildLayoutRecordFromProfile(),
		onApply = function(_, _, data)
			if not self._eqolEditModeHydrated then
				self._eqolEditModeHydrated = true
				local record = data or {}
				seedEditModeRecordFromProfile(record)
				self:ApplyLayoutData(record)
				return
			end
			self:ApplyLayoutData(data)
		end,
		onEnter = function() self:ShowEditModeHint(true) end,
		onExit = function() self:ShowEditModeHint(false) end,
		isEnabled = function() return self:IsEnabled() end,
		settings = settings,
		settingsMaxHeight = DEFAULT_SETTINGS_MAX_HEIGHT,
		showOutsideEditMode = false,
		collapseExclusive = true,
		showReset = false,
		showSettingsReset = false,
		enableOverlayToggle = true,
	})

	editModeRegistered = true
end

function Tracker:OnSettingChanged(enabled)
	if enabled then
		self:EnsureFrame()
		self:RegisterEditMode()
		self:RegisterEvents()
		self:Refresh()
	else
		self:UnregisterEvents()
		if frame then
			frame.editBg:Hide()
			frame.editLabel:Hide()
			frame:Hide()
		end
	end

	if EditMode and EditMode.RefreshFrame then EditMode:RefreshFrame(EDITMODE_ID) end
end

return Tracker
