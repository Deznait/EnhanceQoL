local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.SharedMedia = addon.SharedMedia or {}
addon.SharedMedia.functions = addon.SharedMedia.functions or {}

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_SharedMedia")
local LSM = LibStub("LibSharedMedia-3.0")

-- No explicit tree node; content is shown directly under "Media & Sound" in Core

addon.functions.InitDBValue("sharedMediaSounds", {})

local function RegisterEnabledSounds()
	for _, sound in ipairs(addon.SharedMedia.sounds or {}) do
		if addon.db.sharedMediaSounds[sound.key] then LSM:Register("sound", sound.label, sound.path) end
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, name)
	RegisterEnabledSounds()
	self:UnregisterEvent("PLAYER_LOGIN")
end)

function addon.SharedMedia.functions.UpdateSound(key, enabled)
	addon.db.sharedMediaSounds[key] = enabled
	local sound
	for _, s in ipairs(addon.SharedMedia.sounds or {}) do
		if s.key == key then
			sound = s
			break
		end
	end
	if not sound then return end
	if enabled then
		LSM:Register("sound", sound.label, sound.path)
	else
		if LSM.Unregister then
			local ok = pcall(LSM.Unregister, LSM, "sound", sound.label)
			if not ok then addon.variables.requireReload = true end
		else
			addon.variables.requireReload = true
		end
	end
end

-- Statusbars
LSM:Register("statusbar", "EQOL: Holy", "Interface\\AddOns\\" .. addonName .. "\\Assets\\Holy.tga")
LSM:Register("statusbar", "EQOL: Thunder", "Interface\\AddOns\\" .. addonName .. "\\Assets\\Thunder.tga")
LSM:Register("statusbar", "EQOL: Astral", "Interface\\AddOns\\" .. addonName .. "\\Assets\\Astral.tga")
LSM:Register("statusbar", "EQOL: Rage", "Interface\\AddOns\\" .. addonName .. "\\Assets\\Rage.tga")

-- Custom borders (nine-slice) shared across modules
addon.SharedMedia.customBorders = addon.SharedMedia.customBorders or {}
local customBorders = addon.SharedMedia.customBorders

local BORDER_MEDIA_PATH = "Interface\\AddOns\\" .. addonName .. "\\Border\\"

function addon.SharedMedia.functions.RegisterCustomBorder(id, data)
	if not id or type(id) ~= "string" or id == "" then return end
	if type(data) ~= "table" then return end
	local entry = CopyTable(data)
	entry.id = id
	entry.label = entry.label or id
	entry.type = entry.type or "nineslice"
	entry.mediaPath = entry.mediaPath or ""
	entry.pieces = entry.pieces or {}
	entry.defaultThicknessFactor = entry.defaultThicknessFactor or 0.35
	entry.minThickness = entry.minThickness or 1
	entry.maxThicknessRatio = entry.maxThicknessRatio or 0.75
	entry.cornerScale = entry.cornerScale or 1.1
	entry.cornerMaxRatio = entry.cornerMaxRatio or 0.5
	customBorders[id] = entry
	return entry
end

function addon.SharedMedia.functions.GetCustomBorder(id) return customBorders and customBorders[id] end

function addon.SharedMedia.functions.GetCustomBorderOptions()
	local map = {}
	for borderId, info in pairs(customBorders or {}) do
		map[borderId] = (info and info.label) or borderId
	end
	return map
end

local function ensureCustomBorderTextures(borderFrame, borderId)
	if not borderFrame then return nil end
	borderFrame._customBorderTextures = borderFrame._customBorderTextures or {}
	if borderFrame._customBorderTextures[borderId] then return borderFrame._customBorderTextures[borderId] end

	local layer = "BORDER"
	local pack = {
		tl = borderFrame:CreateTexture(nil, layer),
		tr = borderFrame:CreateTexture(nil, layer),
		bl = borderFrame:CreateTexture(nil, layer),
		br = borderFrame:CreateTexture(nil, layer),
		top = borderFrame:CreateTexture(nil, layer),
		bottom = borderFrame:CreateTexture(nil, layer),
		left = borderFrame:CreateTexture(nil, layer),
		right = borderFrame:CreateTexture(nil, layer),
	}
	borderFrame._customBorderTextures[borderId] = pack
	return pack
end

function addon.SharedMedia.functions.HideCustomBorders(borderFrame)
	if not borderFrame then return end
	local cache = borderFrame._customBorderTextures
	if cache then
		for _, pack in pairs(cache) do
			for _, tex in pairs(pack) do
				if tex and tex.Hide then tex:Hide() end
			end
		end
	end
	borderFrame._activeCustomBorder = nil
	borderFrame._customBorderConfig = nil
end

function addon.SharedMedia.functions.ApplyCustomBorder(borderFrame, bd)
	if not borderFrame or not bd then return false end
	local borderId = bd.borderTexture
	local def = customBorders and customBorders[borderId]
	if not def or def.type ~= "nineslice" then return false end

	local rb = ensureCustomBorderTextures(borderFrame, borderId)
	if not rb then return false end

	local bw, bh = borderFrame:GetSize()
	if not bw or not bh or bw <= 0 or bh <= 0 then
		addon.SharedMedia.functions.HideCustomBorders(borderFrame)
		return false
	end

	local desiredThickness = bd and tonumber(bd.edgeSize)
	if not desiredThickness or desiredThickness <= 0 then desiredThickness = bh * (def.defaultThicknessFactor or 0.35) end
	desiredThickness = max(def.minThickness or 1, desiredThickness)
	desiredThickness = min(desiredThickness, min(bw, bh) * (def.maxThicknessRatio or 0.75))

	local cornerBase = desiredThickness * (def.cornerScale or 1.1)
	local cornerLimit = min(bw, bh) * (def.cornerMaxRatio or 0.5)
	local cornerSize = max(desiredThickness, min(cornerBase, cornerLimit))

	local col = bd and bd.borderColor
	local cr, cg, cb, ca = 1, 1, 1, 1
	if col then
		cr = col[1] or cr
		cg = col[2] or cg
		cb = col[3] or cb
		ca = col[4] or ca
	end

	local function texPath(key)
		local piece = def.pieces and def.pieces[key]
		if not piece then return nil end
		if type(piece) == "string" and piece:find("\\") then return piece end
		return (def.mediaPath or "") .. tostring(piece)
	end

	local function setCorner(tex, texturePath, point)
		if not texturePath then return end
		tex:SetTexture(texturePath)
		tex:ClearAllPoints()
		tex:SetPoint(point)
		tex:SetSize(cornerSize, cornerSize)
		tex:SetVertexColor(cr, cg, cb, ca)
		tex:Show()
	end

	setCorner(rb.tl, texPath("tl"), "TOPLEFT")
	setCorner(rb.tr, texPath("tr"), "TOPRIGHT")
	setCorner(rb.bl, texPath("bl"), "BOTTOMLEFT")
	setCorner(rb.br, texPath("br"), "BOTTOMRIGHT")

	local function setEdge(tex, texturePath, setPointFn)
		if not texturePath then return end
		tex:SetTexture(texturePath)
		tex:ClearAllPoints()
		setPointFn(tex)
		tex:SetVertexColor(cr, cg, cb, ca)
		tex:Show()
	end

	setEdge(rb.top, texPath("top"), function(tex)
		tex:SetPoint("TOPLEFT", rb.tl, "TOPRIGHT", 0, 0)
		tex:SetPoint("TOPRIGHT", rb.tr, "TOPLEFT", 0, 0)
		tex:SetHeight(desiredThickness)
	end)

	setEdge(rb.bottom, texPath("bottom"), function(tex)
		tex:SetPoint("BOTTOMLEFT", rb.bl, "BOTTOMRIGHT", 0, 0)
		tex:SetPoint("BOTTOMRIGHT", rb.br, "BOTTOMLEFT", 0, 0)
		tex:SetHeight(desiredThickness)
	end)

	setEdge(rb.left, texPath("left"), function(tex)
		tex:SetPoint("TOPLEFT", rb.tl, "BOTTOMLEFT", 0, 0)
		tex:SetPoint("BOTTOMLEFT", rb.bl, "TOPLEFT", 0, 0)
		tex:SetWidth(desiredThickness)
	end)

	setEdge(rb.right, texPath("right"), function(tex)
		tex:SetPoint("TOPRIGHT", rb.tr, "BOTTOMRIGHT", 0, 0)
		tex:SetPoint("BOTTOMRIGHT", rb.br, "TOPRIGHT", 0, 0)
		tex:SetWidth(desiredThickness)
	end)

	if not borderFrame._customSizeHooked then
		borderFrame._customSizeHooked = true
		borderFrame:HookScript("OnSizeChanged", function(self)
			if self._activeCustomBorder and self._customBorderConfig then addon.SharedMedia.functions.ApplyCustomBorder(self, self._customBorderConfig) end
		end)
	end
	borderFrame._activeCustomBorder = borderId
	borderFrame._customBorderConfig = bd
	return true
end

-- EQOL default custom borders
addon.SharedMedia.functions.RegisterCustomBorder("EQOL_BORDER_RUNES", {
	label = "EQOL: Runes",
	mediaPath = BORDER_MEDIA_PATH,
	type = "nineslice",
	pieces = {
		tl = "runes_topleft",
		tr = "runes_topright",
		bl = "runes_bottomleft",
		br = "runes_bottomright",
		top = "runes_top",
		bottom = "runes_bottom",
		left = "runes_left",
		right = "runes_right",
	},
	defaultThicknessFactor = 0.35,
	minThickness = 1,
	maxThicknessRatio = 0.75,
	cornerScale = 1.1,
	cornerMaxRatio = 0.5,
})

addon.SharedMedia.functions.RegisterCustomBorder("EQOL_BORDER_GOLDEN", {
	label = "EQOL: Golden",
	mediaPath = BORDER_MEDIA_PATH,
	type = "nineslice",
	pieces = {
		tl = "golden_topleft",
		tr = "golden_topright",
		bl = "golden_bottomleft",
		br = "golden_bottomright",
		top = "golden_top",
		bottom = "golden_bottom",
		left = "golden_left",
		right = "golden_right",
	},
	defaultThicknessFactor = 0.35,
	minThickness = 1,
	maxThicknessRatio = 0.75,
	cornerScale = 1.1,
	cornerMaxRatio = 0.5,
})

addon.SharedMedia.functions.RegisterCustomBorder("EQOL_BORDER_MODERN", {
	label = "EQOL: Modern",
	mediaPath = BORDER_MEDIA_PATH,
	type = "nineslice",
	pieces = {
		tl = "modern_topleft",
		tr = "modern_topright",
		bl = "modern_bottomleft",
		br = "modern_bottomright",
		top = "modern_top",
		bottom = "modern_bottom",
		left = "modern_left",
		right = "modern_right",
	},
	defaultThicknessFactor = 0.35,
	minThickness = 1,
	maxThicknessRatio = 0.75,
	cornerScale = 1.1,
	cornerMaxRatio = 0.5,
})

addon.SharedMedia.functions.RegisterCustomBorder("EQOL_BORDER_CLASSIC", {
	label = "EQOL: Classic",
	mediaPath = BORDER_MEDIA_PATH,
	type = "nineslice",
	pieces = {
		tl = "classic_topleft",
		tr = "classic_topright",
		bl = "classic_bottomleft",
		br = "classic_bottomright",
		top = "classic_top",
		bottom = "classic_bottom",
		left = "classic_left",
		right = "classic_right",
	},
	defaultThicknessFactor = 0.28,
	minThickness = 1,
	maxThicknessRatio = 0.6,
	cornerScale = 1.0,
	cornerMaxRatio = 0.4,
})
