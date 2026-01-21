local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.Aura = addon.Aura or {}
addon.Aura.CooldownPanels = addon.Aura.CooldownPanels or {}
local CooldownPanels = addon.Aura.CooldownPanels
local Helper = CooldownPanels.helper
local EditMode = addon.EditMode
local SettingType = EditMode and EditMode.lib and EditMode.lib.SettingType
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Aura")

CooldownPanels.ENTRY_TYPE = {
	SPELL = "SPELL",
	ITEM = "ITEM",
	SLOT = "SLOT",
}

CooldownPanels.runtime = CooldownPanels.runtime or {}

local DEFAULT_PREVIEW_COUNT = 6
local MAX_PREVIEW_COUNT = 12
local PREVIEW_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local VALID_DIRECTIONS = {
	RIGHT = true,
	LEFT = true,
	UP = true,
	DOWN = true,
}
local STRATA_ORDER = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }
local VALID_STRATA = {}
for _, strata in ipairs(STRATA_ORDER) do
	VALID_STRATA[strata] = true
end

local GetItemInfoInstantFn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemIconByID = C_Item and C_Item.GetItemIconByID
local GetItemCooldownFn = (C_Item and C_Item.GetItemCooldown) or GetItemCooldown
local GetItemCountFn = (C_Item and C_Item.GetItemCount) or GetItemCount
local GetInventoryItemID = GetInventoryItemID
local GetInventoryItemCooldown = GetInventoryItemCooldown
local GetActionInfo = GetActionInfo
local GetCursorInfo = GetCursorInfo
local ClearCursor = ClearCursor
local GetSpellCooldownInfo = C_Spell and C_Spell.GetSpellCooldown or GetSpellCooldown
local GetSpellChargesInfo = C_Spell and C_Spell.GetSpellCharges
local GetPlayerAuraBySpellID = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
local IsSpellKnown = IsSpellKnown
local IsEquippedItem = IsEquippedItem
local GetTime = GetTime
local ActionButtonSpellAlertManager = ActionButtonSpellAlertManager

local directionOptions = {
	{ value = "LEFT", label = _G.HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_LEFT or _G.LEFT or "Left" },
	{ value = "RIGHT", label = _G.HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_RIGHT or _G.RIGHT or "Right" },
	{ value = "UP", label = _G.HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_UP or _G.UP or "Up" },
	{ value = "DOWN", label = _G.HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_DOWN or _G.DOWN or "Down" },
}

local function normalizeId(value)
	local num = tonumber(value)
	if num then return num end
	return value
end

local function getRuntime(panelId)
	local runtime = CooldownPanels.runtime[panelId]
	if not runtime then
		runtime = {}
		CooldownPanels.runtime[panelId] = runtime
	end
	return runtime
end

local getEditor

local function clampNumber(value, minValue, maxValue, fallback)
	local num = tonumber(value)
	if not num then return fallback end
	if minValue and num < minValue then return minValue end
	if maxValue and num > maxValue then return maxValue end
	return num
end

local function clampInt(value, minValue, maxValue, fallback)
	local num = clampNumber(value, minValue, maxValue, fallback)
	if num == nil then return nil end
	return math.floor(num + 0.5)
end

local function normalizeDirection(direction, fallback)
	if direction and VALID_DIRECTIONS[direction] then return direction end
	if fallback and VALID_DIRECTIONS[fallback] then return fallback end
	return "RIGHT"
end

local function normalizeStrata(strata, fallback)
	if type(strata) == "string" then
		local upper = string.upper(strata)
		if VALID_STRATA[upper] then return upper end
	end
	if type(fallback) == "string" then
		local upper = string.upper(fallback)
		if VALID_STRATA[upper] then return upper end
	end
	return "MEDIUM"
end

local function getPreviewCount(panel)
	if not panel or type(panel.order) ~= "table" then return DEFAULT_PREVIEW_COUNT end
	local count = #panel.order
	if count <= 0 then return DEFAULT_PREVIEW_COUNT end
	if count > MAX_PREVIEW_COUNT then return MAX_PREVIEW_COUNT end
	return count
end

local function getEntryIcon(entry)
	if not entry or type(entry) ~= "table" then return PREVIEW_ICON end
	if entry.type == "SPELL" and entry.spellID then return (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(entry.spellID)) or PREVIEW_ICON end
	if entry.type == "ITEM" and entry.itemID then
		if GetItemIconByID then
			local icon = GetItemIconByID(entry.itemID)
			if icon then return icon end
		end
		if GetItemInfoInstantFn then
			local _, _, _, _, icon = GetItemInfoInstantFn(entry.itemID)
			if icon then return icon end
		end
	end
	if entry.type == "SLOT" and entry.slotID and GetInventoryItemID then
		local itemID = GetInventoryItemID("player", entry.slotID)
		if itemID then
			if GetItemIconByID then
				local icon = GetItemIconByID(itemID)
				if icon then return icon end
			end
			if GetItemInfoInstantFn then
				local _, _, _, _, icon = GetItemInfoInstantFn(itemID)
				if icon then return icon end
			end
		end
	end
	return PREVIEW_ICON
end

local SLOT_LABELS = {
	[13] = L["CooldownPanelSlotTrinket1"] or "Trinket 1",
	[14] = L["CooldownPanelSlotTrinket2"] or "Trinket 2",
	[16] = L["CooldownPanelSlotMainHand"] or "Main Hand",
	[17] = L["CooldownPanelSlotOffHand"] or "Off Hand",
}

local function getSlotLabel(slotId) return SLOT_LABELS[slotId] or ("Slot " .. tostring(slotId)) end

local function getSpellName(spellId)
	if not spellId then return nil end
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(spellId)
		if info and info.name then return info.name end
	end
	if GetSpellInfo then
		local name = GetSpellInfo(spellId)
		if name then return name end
	end
	return nil
end

local function getItemName(itemId)
	if not itemId then return nil end
	if C_Item and C_Item.GetItemNameByID then
		local name = C_Item.GetItemNameByID(itemId)
		if name then return name end
	end
	if GetItemInfo then
		local name = GetItemInfo(itemId)
		if name then return name end
	end
	return nil
end

local function getEntryName(entry)
	if not entry then return "" end
	if entry.type == "SPELL" then
		local name = getSpellName(entry.spellID)
		return name or ("Spell " .. tostring(entry.spellID or ""))
	end
	if entry.type == "ITEM" then
		local name = getItemName(entry.itemID)
		return name or ("Item " .. tostring(entry.itemID or ""))
	end
	if entry.type == "SLOT" then return getSlotLabel(entry.slotID) end
	return "Entry"
end

local function isSpellKnownSafe(spellId)
	if not spellId then return false end
	if C_Spell and C_Spell.IsSpellKnown then
		local ok, known = pcall(C_Spell.IsSpellKnown, spellId)
		if ok then return known and true or false end
	end
	if IsSpellKnown then
		local ok, known = pcall(IsSpellKnown, spellId)
		if ok then return known and true or false end
	end
	if C_SpellBook and C_SpellBook.IsSpellInSpellBook then
		local ok, known = pcall(C_SpellBook.IsSpellInSpellBook, spellId)
		if ok then return known and true or false end
	end
	return true
end

local function showErrorMessage(msg)
	if UIErrorsFrame and msg then UIErrorsFrame:AddMessage(msg, 1, 0.2, 0.2, 1) end
end

local function ensureRoot()
	if not addon.db then return nil end
	if type(addon.db.cooldownPanels) ~= "table" then
		addon.db.cooldownPanels = Helper.CreateRoot()
	else
		Helper.NormalizeRoot(addon.db.cooldownPanels)
	end
	return addon.db.cooldownPanels
end

function CooldownPanels:EnsureDB() return ensureRoot() end

function CooldownPanels:GetRoot() return ensureRoot() end

function CooldownPanels:GetPanel(panelId)
	local root = ensureRoot()
	if not root then return nil end
	panelId = normalizeId(panelId)
	local panel = root.panels and root.panels[panelId]
	if panel then Helper.NormalizePanel(panel, root.defaults) end
	return panel
end

function CooldownPanels:GetPanelOrder()
	local root = ensureRoot()
	if not root then return nil end
	return root.order
end

function CooldownPanels:SetPanelOrder(order)
	local root = ensureRoot()
	if not root or type(order) ~= "table" then return end
	root.order = order
	Helper.SyncOrder(root.order, root.panels)
end

function CooldownPanels:SetSelectedPanel(panelId)
	local root = ensureRoot()
	if not root then return end
	panelId = normalizeId(panelId)
	if root.panels and root.panels[panelId] then root.selectedPanel = panelId end
end

function CooldownPanels:GetSelectedPanel()
	local root = ensureRoot()
	if not root then return nil end
	return root.selectedPanel
end

function CooldownPanels:CreatePanel(name)
	local root = ensureRoot()
	if not root then return nil end
	local id = Helper.GetNextNumericId(root.panels)
	local panel = Helper.CreatePanel(name, root.defaults)
	panel.id = id
	root.panels[id] = panel
	root.order[#root.order + 1] = id
	if not root.selectedPanel then root.selectedPanel = id end
	self:RegisterEditModePanel(id)
	self:RefreshPanel(id)
	return id, panel
end

function CooldownPanels:DeletePanel(panelId)
	local root = ensureRoot()
	panelId = normalizeId(panelId)
	if not root or not root.panels or not root.panels[panelId] then return end
	root.panels[panelId] = nil
	Helper.SyncOrder(root.order, root.panels)
	if root.selectedPanel == panelId then root.selectedPanel = root.order[1] end
	local runtime = CooldownPanels.runtime and CooldownPanels.runtime[panelId]
	if runtime then
		if runtime.editModeId and EditMode and EditMode.UnregisterFrame then pcall(EditMode.UnregisterFrame, EditMode, runtime.editModeId) end
		if runtime.frame then
			runtime.frame:Hide()
			runtime.frame:SetParent(nil)
			runtime.frame = nil
		end
		CooldownPanels.runtime[panelId] = nil
	end
end

function CooldownPanels:AddEntry(panelId, entryType, idValue, overrides)
	local root = ensureRoot()
	if not root then return nil end
	panelId = normalizeId(panelId)
	local panel = self:GetPanel(panelId)
	if not panel then return nil end
	local typeKey = entryType and tostring(entryType):upper() or nil
	if typeKey ~= "SPELL" and typeKey ~= "ITEM" and typeKey ~= "SLOT" then return nil end
	local numericValue = tonumber(idValue)
	if not numericValue then return nil end
	local entryId = Helper.GetNextNumericId(panel.entries)
	local entry = Helper.CreateEntry(typeKey, numericValue, root.defaults)
	entry.id = entryId
	if type(overrides) == "table" then
		for key, value in pairs(overrides) do
			entry[key] = value
		end
	end
	panel.entries[entryId] = entry
	panel.order[#panel.order + 1] = entryId
	self:RefreshPanel(panelId)
	return entryId, entry
end

function CooldownPanels:FindEntryByValue(panelId, entryType, idValue)
	panelId = normalizeId(panelId)
	local panel = self:GetPanel(panelId)
	if not panel then return nil end
	local typeKey = entryType and tostring(entryType):upper() or nil
	local numericValue = tonumber(idValue)
	if typeKey ~= "SPELL" and typeKey ~= "ITEM" and typeKey ~= "SLOT" then return nil end
	for entryId, entry in pairs(panel.entries or {}) do
		if entry and entry.type == typeKey then
			if typeKey == "SPELL" and entry.spellID == numericValue then return entryId, entry end
			if typeKey == "ITEM" and entry.itemID == numericValue then return entryId, entry end
			if typeKey == "SLOT" and entry.slotID == numericValue then return entryId, entry end
		end
	end
	return nil
end

function CooldownPanels:RemoveEntry(panelId, entryId)
	panelId = normalizeId(panelId)
	entryId = normalizeId(entryId)
	local panel = self:GetPanel(panelId)
	if not panel or not panel.entries or not panel.entries[entryId] then return end
	panel.entries[entryId] = nil
	Helper.SyncOrder(panel.order, panel.entries)
	self:RefreshPanel(panelId)
end

function CooldownPanels:NormalizeAll()
	local root = ensureRoot()
	if not root then return end
	Helper.NormalizeRoot(root)
	Helper.SyncOrder(root.order, root.panels)
	for panelId, panel in pairs(root.panels) do
		if panel and panel.id == nil then panel.id = panelId end
		Helper.NormalizePanel(panel, root.defaults)
		Helper.SyncOrder(panel.order, panel.entries)
		for entryId, entry in pairs(panel.entries) do
			if entry and entry.id == nil then entry.id = entryId end
			Helper.NormalizeEntry(entry, root.defaults)
		end
	end
end

function CooldownPanels:AddEntrySafe(panelId, entryType, idValue, overrides)
	local typeKey = entryType and tostring(entryType):upper() or nil
	local numericValue = tonumber(idValue)
	if typeKey == "SPELL" and numericValue and not isSpellKnownSafe(numericValue) then
		showErrorMessage(SPELL_FAILED_NOT_KNOWN or "Spell not known.")
		return nil
	end
	if self:FindEntryByValue(panelId, typeKey, numericValue) then
		showErrorMessage(L["CooldownPanelEntry"] and (L["CooldownPanelEntry"] .. " already exists.") or "Entry already exists.")
		return nil
	end
	return self:AddEntry(panelId, typeKey, numericValue, overrides)
end

function CooldownPanels:HandleCursorDrop(panelId)
	panelId = normalizeId(panelId or self:GetSelectedPanel())
	if not panelId then return false end
	local cursorType, cursorId, _, cursorSpellId = GetCursorInfo()
	if not cursorType then return false end

	local added = false
	if cursorType == "spell" then
		local spellId = cursorSpellId or cursorId
		if spellId then added = self:AddEntrySafe(panelId, "SPELL", spellId) ~= nil end
	elseif cursorType == "item" then
		if cursorId then added = self:AddEntrySafe(panelId, "ITEM", cursorId) ~= nil end
	elseif cursorType == "action" and GetActionInfo then
		local actionType, actionId = GetActionInfo(cursorId)
		if actionType == "spell" then
			added = self:AddEntrySafe(panelId, "SPELL", actionId) ~= nil
		elseif actionType == "item" then
			added = self:AddEntrySafe(panelId, "ITEM", actionId) ~= nil
		end
	end

	if added then ClearCursor() end
	return added
end

function CooldownPanels:SelectPanel(panelId)
	local root = ensureRoot()
	if not root then return end
	panelId = normalizeId(panelId)
	if not root.panels or not root.panels[panelId] then return end
	root.selectedPanel = panelId
	local editor = getEditor()
	if editor then
		editor.selectedPanelId = panelId
		editor.selectedEntryId = nil
	end
	self:RefreshEditor()
end

function CooldownPanels:SelectEntry(entryId)
	entryId = normalizeId(entryId)
	local editor = getEditor()
	if not editor then return end
	editor.selectedEntryId = entryId
	self:RefreshEditor()
end

local function createIconFrame(parent)
	local icon = CreateFrame("Frame", nil, parent)
	icon:Hide()

	icon.texture = icon:CreateTexture(nil, "ARTWORK")
	icon.texture:SetAllPoints(icon)

	icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
	icon.cooldown:SetAllPoints(icon)
	icon.cooldown:SetHideCountdownNumbers(true)

	icon.count = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	icon.count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
	icon.count:Hide()

	icon.charges = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	icon.charges:SetPoint("TOP", icon, "TOP", 0, -1)
	icon.charges:Hide()

	return icon
end

local function ensureIconCount(frame, count)
	frame.icons = frame.icons or {}
	for i = 1, count do
		if not frame.icons[i] then frame.icons[i] = createIconFrame(frame) end
		frame.icons[i]:Show()
	end
	for i = count + 1, #frame.icons do
		frame.icons[i]:Hide()
	end
end

local function setGlow(frame, enabled)
	if frame._glow == enabled then return end
	frame._glow = enabled
	if not ActionButtonSpellAlertManager then return end
	if enabled then
		ActionButtonSpellAlertManager:ShowAlert(frame)
	else
		ActionButtonSpellAlertManager:HideAlert(frame)
	end
end

local function isCooldownActive(startTime, duration)
	if not startTime or not duration then return false end
	if duration <= 0 or startTime <= 0 then return false end
	if not GetTime then return false end
	return (startTime + duration) > GetTime()
end

local function getSpellCooldownInfo(spellID)
	if not spellID or not GetSpellCooldownInfo then return 0, 0, false, 1 end
	local a, b, c, d = GetSpellCooldownInfo(spellID)
	if type(a) == "table" then return a.startTime or 0, a.duration or 0, a.isEnabled, a.modRate or 1 end
	return a or 0, b or 0, c, d or 1
end

local function getItemCooldownInfo(itemID, slotID)
	if slotID and GetInventoryItemCooldown then
		local start, duration, enabled = GetInventoryItemCooldown("player", slotID)
		if start and duration then return start, duration, enabled end
	end
	if not itemID or not GetItemCooldownFn then return 0, 0, false end
	local start, duration, enabled = GetItemCooldownFn(itemID)
	return start or 0, duration or 0, enabled
end

local function hasItem(itemID)
	if not itemID then return false end
	if IsEquippedItem and IsEquippedItem(itemID) then return true end
	if GetItemCountFn then
		local count = GetItemCountFn(itemID, true)
		if count and count > 0 then return true end
	end
	return false
end

local function createPanelFrame(panelId, panel)
	local frame = CreateFrame("Button", "EQOL_CooldownPanel" .. tostring(panelId), UIParent)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(false)
	frame.panelId = panelId
	frame.icons = {}

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(frame)
	bg:SetColorTexture(0.1, 0.6, 0.6, 0.2)
	bg:Hide()
	frame.bg = bg

	local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("CENTER")
	label:SetText(panel and panel.name or "Cooldown Panel")
	label:Hide()
	frame.label = label

	frame:RegisterForClicks("LeftButtonUp")
	frame:SetScript("OnReceiveDrag", function(self)
		if not (CooldownPanels and CooldownPanels.IsInEditMode and CooldownPanels:IsInEditMode()) then return end
		if CooldownPanels:HandleCursorDrop(self.panelId) then
			CooldownPanels:RefreshPanel(self.panelId)
			if CooldownPanels:IsEditorOpen() then CooldownPanels:RefreshEditor() end
		end
	end)
	frame:SetScript("OnMouseUp", function(self, btn)
		if btn ~= "LeftButton" then return end
		if not (CooldownPanels and CooldownPanels.IsInEditMode and CooldownPanels:IsInEditMode()) then return end
		if CooldownPanels:HandleCursorDrop(self.panelId) then
			CooldownPanels:RefreshPanel(self.panelId)
			if CooldownPanels:IsEditorOpen() then CooldownPanels:RefreshEditor() end
		end
	end)

	return frame
end

local function getGridDimensions(count, wrapCount, primaryHorizontal)
	if count < 1 then count = 1 end
	if wrapCount and wrapCount > 0 then
		if primaryHorizontal then
			local cols = math.min(count, wrapCount)
			local rows = math.floor((count + wrapCount - 1) / wrapCount)
			return cols, rows
		end
		local rows = math.min(count, wrapCount)
		local cols = math.floor((count + wrapCount - 1) / wrapCount)
		return cols, rows
	end
	if primaryHorizontal then return count, 1 end
	return 1, count
end

local function containsId(list, id)
	if type(list) ~= "table" then return false end
	for _, value in ipairs(list) do
		if value == id then return true end
	end
	return false
end

local function applyIconLayout(frame, count, layout)
	if not frame then return end
	local iconSize = clampInt(layout.iconSize, 12, 128, Helper.PANEL_LAYOUT_DEFAULTS.iconSize)
	local spacing = clampInt(layout.spacing, 0, 50, Helper.PANEL_LAYOUT_DEFAULTS.spacing)
	local direction = normalizeDirection(layout.direction, Helper.PANEL_LAYOUT_DEFAULTS.direction)
	local wrapCount = clampInt(layout.wrapCount, 0, 40, Helper.PANEL_LAYOUT_DEFAULTS.wrapCount or 0)
	local wrapDirection = normalizeDirection(layout.wrapDirection, Helper.PANEL_LAYOUT_DEFAULTS.wrapDirection or "DOWN")
	local primaryHorizontal = direction == "LEFT" or direction == "RIGHT"

	local cols, rows = getGridDimensions(count, wrapCount, primaryHorizontal)
	local step = iconSize + spacing
	local width = (cols * iconSize) + ((cols - 1) * spacing)
	local height = (rows * iconSize) + ((rows - 1) * spacing)

	frame:SetSize(width > 0 and width or iconSize, height > 0 and height or iconSize)
	ensureIconCount(frame, count)

	for i = 1, count do
		local icon = frame.icons[i]
		local primaryIndex = i - 1
		local secondaryIndex = 0
		if wrapCount and wrapCount > 0 then
			primaryIndex = (i - 1) % wrapCount
			secondaryIndex = math.floor((i - 1) / wrapCount)
		end

		local col, row
		if primaryHorizontal then
			col = primaryIndex
			row = secondaryIndex
		else
			row = primaryIndex
			col = secondaryIndex
		end

		if primaryHorizontal and direction == "LEFT" then
			col = (cols - 1) - col
		elseif (not primaryHorizontal) and direction == "UP" then
			row = (rows - 1) - row
		end

		if primaryHorizontal then
			if wrapDirection == "UP" then row = (rows - 1) - row end
		else
			if wrapDirection == "LEFT" then col = (cols - 1) - col end
		end

		icon:SetSize(iconSize, iconSize)
		icon:ClearAllPoints()
		icon:SetPoint("TOPLEFT", frame, "TOPLEFT", col * step, -row * step)
	end
end

local function applyPanelBorder(frame)
	local borderLayer, borderSubLevel = "BORDER", 0
	local borderPath = "Interface\\AddOns\\EnhanceQoL\\Assets\\PanelBorder_"
	local cornerSize = 70
	local edgeThickness = 70
	local cornerOffsets = 13

	local function makeTex(key, layer, subLevel)
		local tex = frame:CreateTexture(nil, layer or borderLayer, nil, subLevel or borderSubLevel)
		tex:SetTexture(borderPath .. key .. ".tga")
		tex:SetAlpha(0.95)
		return tex
	end

	local tl = makeTex("tl", borderLayer, borderSubLevel + 1)
	tl:SetSize(cornerSize, cornerSize)
	tl:SetPoint("TOPLEFT", frame, "TOPLEFT", -cornerOffsets, cornerOffsets)

	local tr = makeTex("tr", borderLayer, borderSubLevel + 1)
	tr:SetSize(cornerSize, cornerSize)
	tr:SetPoint("TOPRIGHT", frame, "TOPRIGHT", cornerOffsets + 8, cornerOffsets)

	local bl = makeTex("bl", borderLayer, borderSubLevel + 1)
	bl:SetSize(cornerSize, cornerSize)
	bl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -cornerOffsets, -cornerOffsets)

	local br = makeTex("br", borderLayer, borderSubLevel + 1)
	br:SetSize(cornerSize, cornerSize)
	br:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", cornerOffsets + 8, -cornerOffsets)

	local top = makeTex("t", borderLayer, borderSubLevel)
	top:SetPoint("TOPLEFT", tl, "TOPRIGHT", 0, 0)
	top:SetPoint("TOPRIGHT", tr, "TOPLEFT", 0, 0)
	top:SetHeight(edgeThickness)
	top:SetHorizTile(true)

	local bottom = makeTex("b", borderLayer, borderSubLevel)
	bottom:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT", 0, 0)
	bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT", 0, 0)
	bottom:SetHeight(edgeThickness)
	bottom:SetHorizTile(true)

	local left = makeTex("l", borderLayer, borderSubLevel)
	left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", bl, "TOPLEFT", 0, 0)
	left:SetWidth(edgeThickness)
	left:SetVertTile(true)

	local right = makeTex("r", borderLayer, borderSubLevel)
	right:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT", 0, 0)
	right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT", 0, 0)
	right:SetWidth(edgeThickness)
	right:SetVertTile(true)
end

local function applyInsetBorder(frame, offset)
	if not frame then return end
	offset = offset or 10

	local layer, subLevel = "BORDER", 2
	local path = "Interface\\AddOns\\EnhanceQoL\\Assets\\border_round_"
	local cornerSize = 36
	local edgeSize = 36

	frame.eqolInsetParts = frame.eqolInsetParts or {}
	local parts = frame.eqolInsetParts

	local function tex(name)
		if not parts[name] then parts[name] = frame:CreateTexture(nil, layer, nil, subLevel) end
		local t = parts[name]
		t:SetAlpha(0.7)
		t:SetTexture(path .. name .. ".tga")
		t:SetDrawLayer(layer, subLevel)
		return t
	end

	local tl = tex("tl")
	tl:SetSize(cornerSize, cornerSize)
	tl:ClearAllPoints()
	tl:SetPoint("TOPLEFT", frame, "TOPLEFT", offset, -offset)

	local tr = tex("tr")
	tr:SetSize(cornerSize, cornerSize)
	tr:ClearAllPoints()
	tr:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -offset, -offset)

	local bl = tex("bl")
	bl:SetSize(cornerSize, cornerSize)
	bl:ClearAllPoints()
	bl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", offset, offset)

	local br = tex("br")
	br:SetSize(cornerSize, cornerSize)
	br:ClearAllPoints()
	br:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -offset, offset)

	local top = tex("t")
	top:ClearAllPoints()
	top:SetPoint("TOPLEFT", tl, "TOPRIGHT", 0, 0)
	top:SetPoint("TOPRIGHT", tr, "TOPLEFT", 0, 0)
	top:SetHeight(edgeSize)
	top:SetHorizTile(true)

	local bottom = tex("b")
	bottom:ClearAllPoints()
	bottom:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT", 0, 0)
	bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT", 0, 0)
	bottom:SetHeight(edgeSize)
	bottom:SetHorizTile(true)

	local left = tex("l")
	left:ClearAllPoints()
	left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", bl, "TOPLEFT", 0, 0)
	left:SetWidth(edgeSize)
	left:SetVertTile(true)

	local right = tex("r")
	right:ClearAllPoints()
	right:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT", 0, 0)
	right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT", 0, 0)
	right:SetWidth(edgeSize)
	right:SetVertTile(true)
end

local function createLabel(parent, text, size, style)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetText(text or "")
	label:SetFont((addon.variables and addon.variables.defaultFont) or label:GetFont(), size or 12, style or "OUTLINE")
	label:SetTextColor(1, 0.82, 0, 1)
	return label
end

local function createButton(parent, text, width, height)
	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	btn:SetText(text or "")
	btn:SetSize(width or 120, height or 22)
	return btn
end

local function createEditBox(parent, width, height)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(width or 120, height or 22)
	box:SetAutoFocus(false)
	box:SetFontObject(GameFontHighlightSmall)
	return box
end

local function createCheck(parent, text)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb.Text:SetText(text or "")
	cb.Text:SetTextColor(1, 1, 1, 1)
	return cb
end

local function createRowButton(parent, height)
	local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
	row:SetHeight(height or 28)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints(row)
	row.bg:SetColorTexture(0, 0, 0, 0.2)
	row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
	row.highlight:SetAllPoints(row)
	row.highlight:SetColorTexture(1, 1, 1, 0.06)
	return row
end

getEditor = function()
	local runtime = CooldownPanels.runtime and CooldownPanels.runtime["editor"]
	return runtime and runtime.editor or nil
end

local function ensureEditor()
	local runtime = getRuntime("editor")
	if runtime.editor then return runtime.editor end

	local frame = CreateFrame("Frame", "EQOL_CooldownPanelsEditor", UIParent, "BackdropTemplate")
	frame:SetSize(980, 560)
	frame:SetPoint("CENTER")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetFrameStrata("DIALOG")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()

	frame.bg = frame:CreateTexture(nil, "BACKGROUND")
	frame.bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
	frame.bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 10)
	frame.bg:SetTexture("Interface\\AddOns\\EnhanceQoL\\Assets\\background_dark.tga")
	frame.bg:SetAlpha(0.9)
	applyPanelBorder(frame)

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -12)
	frame.title:SetText(L["CooldownPanelEditor"] or "Cooldown Panel Editor")
	frame.title:SetFont((addon.variables and addon.variables.defaultFont) or frame.title:GetFont(), 16, "OUTLINE")

	frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 8, 8)

	local left = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	left:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -44)
	left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 16)
	left:SetWidth(220)
	left.bg = left:CreateTexture(nil, "BACKGROUND")
	left.bg:SetAllPoints(left)
	left.bg:SetTexture("Interface\\AddOns\\EnhanceQoL\\Assets\\background_gray.tga")
	left.bg:SetAlpha(0.85)
	applyInsetBorder(left, -4)
	frame.left = left

	local panelTitle = createLabel(left, L["CooldownPanelPanels"] or "Panels", 12, "OUTLINE")
	panelTitle:SetPoint("TOPLEFT", left, "TOPLEFT", 12, -12)

	local panelScroll = CreateFrame("ScrollFrame", nil, left, "UIPanelScrollFrameTemplate")
	panelScroll:SetPoint("TOPLEFT", panelTitle, "BOTTOMLEFT", 0, -8)
	panelScroll:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -26, 44)
	local panelContent = CreateFrame("Frame", nil, panelScroll)
	panelContent:SetSize(1, 1)
	panelScroll:SetScrollChild(panelContent)
	panelContent:SetWidth(panelScroll:GetWidth() or 1)
	panelScroll:SetScript("OnSizeChanged", function(self) panelContent:SetWidth(self:GetWidth() or 1) end)

	local addPanel = createButton(left, L["CooldownPanelAddPanel"] or "Add Panel", 96, 22)
	addPanel:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 12, 12)

	local deletePanel = createButton(left, L["CooldownPanelDeletePanel"] or "Delete Panel", 96, 22)
	deletePanel:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -12, 12)

	local right = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -44)
	right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
	right:SetWidth(260)
	right.bg = right:CreateTexture(nil, "BACKGROUND")
	right.bg:SetAllPoints(right)
	right.bg:SetTexture("Interface\\AddOns\\EnhanceQoL\\Assets\\background_gray.tga")
	right.bg:SetAlpha(0.85)
	applyInsetBorder(right, -4)
	frame.right = right

	local panelHeader = createLabel(right, L["CooldownPanelPanels"] or "Panels", 12, "OUTLINE")
	panelHeader:SetPoint("TOPLEFT", right, "TOPLEFT", 12, -12)
	panelHeader:SetTextColor(0.9, 0.9, 0.9, 1)

	local panelNameLabel = createLabel(right, L["CooldownPanelPanelName"] or "Panel name", 11, "OUTLINE")
	panelNameLabel:SetPoint("TOPLEFT", panelHeader, "BOTTOMLEFT", 0, -8)
	panelNameLabel:SetTextColor(0.9, 0.9, 0.9, 1)

	local panelNameBox = createEditBox(right, 200, 20)
	panelNameBox:SetPoint("TOPLEFT", panelNameLabel, "BOTTOMLEFT", 0, -4)

	local panelEnabled = createCheck(right, L["CooldownPanelEnabled"] or "Enabled")
	panelEnabled:SetPoint("TOPLEFT", panelNameBox, "BOTTOMLEFT", -2, -6)

	local entryHeader = createLabel(right, L["CooldownPanelEntry"] or "Entry", 12, "OUTLINE")
	entryHeader:SetPoint("TOPLEFT", panelEnabled, "BOTTOMLEFT", 2, -16)
	entryHeader:SetTextColor(0.9, 0.9, 0.9, 1)

	local entryIcon = right:CreateTexture(nil, "ARTWORK")
	entryIcon:SetSize(36, 36)
	entryIcon:SetPoint("TOPLEFT", entryHeader, "BOTTOMLEFT", 0, -6)
	entryIcon:SetTexture(PREVIEW_ICON)

	local entryName = right:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	entryName:SetPoint("LEFT", entryIcon, "RIGHT", 8, 8)
	entryName:SetWidth(180)
	entryName:SetJustifyH("LEFT")
	entryName:SetTextColor(1, 1, 1, 1)

	local entryType = right:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	entryType:SetPoint("TOPLEFT", entryName, "BOTTOMLEFT", 0, -2)
	entryType:SetJustifyH("LEFT")

	local entryIdBox = createEditBox(right, 120, 20)
	entryIdBox:SetPoint("TOPLEFT", entryIcon, "BOTTOMLEFT", 0, -8)
	entryIdBox:SetNumeric(true)

	local cbAlways = createCheck(right, L["CooldownPanelAlwaysShow"] or "Always show")
	cbAlways:SetPoint("TOPLEFT", entryIdBox, "BOTTOMLEFT", -2, -6)

	local cbCooldown = createCheck(right, L["CooldownPanelShowCooldown"] or "Show cooldown")
	cbCooldown:SetPoint("TOPLEFT", cbAlways, "BOTTOMLEFT", 0, -4)

	local cbCharges = createCheck(right, L["CooldownPanelShowCharges"] or "Show charges")
	cbCharges:SetPoint("TOPLEFT", cbCooldown, "BOTTOMLEFT", 0, -4)

	local cbStacks = createCheck(right, L["CooldownPanelShowStacks"] or "Show stack count")
	cbStacks:SetPoint("TOPLEFT", cbCharges, "BOTTOMLEFT", 0, -4)

	local cbGlow = createCheck(right, L["CooldownPanelGlowReady"] or "Glow when ready")
	cbGlow:SetPoint("TOPLEFT", cbStacks, "BOTTOMLEFT", 0, -4)

	local removeEntry = createButton(right, L["CooldownPanelRemoveEntry"] or "Remove entry", 180, 22)
	removeEntry:SetPoint("BOTTOM", right, "BOTTOM", 0, 14)

	local middle = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	middle:SetPoint("TOPLEFT", left, "TOPRIGHT", 16, 0)
	middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", -16, 0)
	middle.bg = middle:CreateTexture(nil, "BACKGROUND")
	middle.bg:SetAllPoints(middle)
	middle.bg:SetTexture("Interface\\AddOns\\EnhanceQoL\\Assets\\background_gray.tga")
	middle.bg:SetAlpha(0.85)
	applyInsetBorder(middle, -4)
	frame.middle = middle

	local previewTitle = createLabel(middle, L["CooldownPanelPreview"] or "Preview", 12, "OUTLINE")
	previewTitle:SetPoint("TOPLEFT", middle, "TOPLEFT", 12, -12)

	local previewFrame = CreateFrame("Frame", nil, middle, "BackdropTemplate")
	previewFrame:SetPoint("TOPLEFT", middle, "TOPLEFT", 12, -36)
	previewFrame:SetPoint("TOPRIGHT", middle, "TOPRIGHT", -12, -36)
	previewFrame:SetHeight(190)
	previewFrame.bg = previewFrame:CreateTexture(nil, "BACKGROUND")
	previewFrame.bg:SetAllPoints(previewFrame)
	previewFrame.bg:SetColorTexture(0, 0, 0, 0.3)
	applyInsetBorder(previewFrame, -6)

	local previewCanvas = CreateFrame("Frame", nil, previewFrame)
	previewCanvas:SetPoint("CENTER", previewFrame, "CENTER")
	previewFrame.canvas = previewCanvas

	local previewHint = previewFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	previewHint:SetPoint("CENTER", previewFrame, "CENTER")
	previewHint:SetText(L["CooldownPanelDropHint"] or "Drop spells or items here")
	previewHint:SetTextColor(0.7, 0.7, 0.7, 1)
	previewFrame.dropHint = previewHint

	local dropZone = CreateFrame("Button", nil, previewFrame)
	dropZone:SetAllPoints(previewFrame)
	dropZone:RegisterForClicks("LeftButtonUp")
	dropZone:SetScript("OnReceiveDrag", function()
		if CooldownPanels:HandleCursorDrop(runtime.editor and runtime.editor.selectedPanelId) then CooldownPanels:RefreshEditor() end
	end)
	dropZone:SetScript("OnMouseUp", function(_, btn)
		if btn == "LeftButton" then
			if CooldownPanels:HandleCursorDrop(runtime.editor and runtime.editor.selectedPanelId) then CooldownPanels:RefreshEditor() end
		end
	end)
	dropZone.highlight = dropZone:CreateTexture(nil, "HIGHLIGHT")
	dropZone.highlight:SetAllPoints(dropZone)
	dropZone.highlight:SetColorTexture(0.2, 0.6, 0.6, 0.15)
	previewFrame.dropZone = dropZone

	local entryTitle = createLabel(middle, L["CooldownPanelEntries"] or "Entries", 12, "OUTLINE")
	entryTitle:SetPoint("TOPLEFT", previewFrame, "BOTTOMLEFT", 0, -12)

	local entryScroll = CreateFrame("ScrollFrame", nil, middle, "UIPanelScrollFrameTemplate")
	entryScroll:SetPoint("TOPLEFT", entryTitle, "BOTTOMLEFT", 0, -8)
	entryScroll:SetPoint("BOTTOMRIGHT", middle, "BOTTOMRIGHT", -26, 80)
	local entryContent = CreateFrame("Frame", nil, entryScroll)
	entryContent:SetSize(1, 1)
	entryScroll:SetScrollChild(entryContent)
	entryContent:SetWidth(entryScroll:GetWidth() or 1)
	entryScroll:SetScript("OnSizeChanged", function(self) entryContent:SetWidth(self:GetWidth() or 1) end)

	local addSpellLabel = createLabel(middle, L["CooldownPanelAddSpellID"] or "Add Spell ID", 11, "OUTLINE")
	addSpellLabel:SetPoint("BOTTOMLEFT", middle, "BOTTOMLEFT", 12, 46)
	addSpellLabel:SetTextColor(0.9, 0.9, 0.9, 1)

	local addSpellBox = createEditBox(middle, 80, 20)
	addSpellBox:SetPoint("LEFT", addSpellLabel, "RIGHT", 6, 0)
	addSpellBox:SetNumeric(true)

	local addItemLabel = createLabel(middle, L["CooldownPanelAddItemID"] or "Add Item ID", 11, "OUTLINE")
	addItemLabel:SetPoint("BOTTOMLEFT", middle, "BOTTOMLEFT", 12, 20)
	addItemLabel:SetTextColor(0.9, 0.9, 0.9, 1)

	local addItemBox = createEditBox(middle, 80, 20)
	addItemBox:SetPoint("LEFT", addItemLabel, "RIGHT", 6, 0)
	addItemBox:SetNumeric(true)

	local slotLabel = createLabel(middle, L["CooldownPanelAddSlot"] or "Add Slot", 11, "OUTLINE")
	slotLabel:SetPoint("BOTTOMRIGHT", middle, "BOTTOMRIGHT", -12, 46)
	slotLabel:SetTextColor(0.9, 0.9, 0.9, 1)

	local slotTrinket1 = createButton(middle, L["CooldownPanelSlotTrinket1"] or "Trinket 1", 86, 20)
	slotTrinket1:SetPoint("BOTTOMRIGHT", middle, "BOTTOMRIGHT", -12, 22)

	local slotTrinket2 = createButton(middle, L["CooldownPanelSlotTrinket2"] or "Trinket 2", 86, 20)
	slotTrinket2:SetPoint("RIGHT", slotTrinket1, "LEFT", -6, 0)

	local slotMainHand = createButton(middle, L["CooldownPanelSlotMainHand"] or "Main Hand", 86, 20)
	slotMainHand:SetPoint("BOTTOMRIGHT", middle, "BOTTOMRIGHT", -12, 2)

	local slotOffHand = createButton(middle, L["CooldownPanelSlotOffHand"] or "Off Hand", 86, 20)
	slotOffHand:SetPoint("RIGHT", slotMainHand, "LEFT", -6, 0)

	frame:SetScript("OnShow", function() CooldownPanels:RefreshEditor() end)

	runtime.editor = {
		frame = frame,
		selectedPanelId = nil,
		selectedEntryId = nil,
		panelRows = {},
		entryRows = {},
		panelList = { scroll = panelScroll, content = panelContent },
		entryList = { scroll = entryScroll, content = entryContent },
		previewFrame = previewFrame,
		addPanel = addPanel,
		deletePanel = deletePanel,
		addSpellBox = addSpellBox,
		addItemBox = addItemBox,
		slotButtons = {
			trinket1 = slotTrinket1,
			trinket2 = slotTrinket2,
			mainHand = slotMainHand,
			offHand = slotOffHand,
		},
		inspector = {
			panelName = panelNameBox,
			panelEnabled = panelEnabled,
			entryIcon = entryIcon,
			entryName = entryName,
			entryType = entryType,
			entryId = entryIdBox,
			cbAlways = cbAlways,
			cbCooldown = cbCooldown,
			cbCharges = cbCharges,
			cbStacks = cbStacks,
			cbGlow = cbGlow,
			removeEntry = removeEntry,
		},
	}

	local editor = runtime.editor

	addPanel:SetScript("OnClick", function()
		local newName = L["CooldownPanelNewPanel"] or "New Panel"
		local panelId = CooldownPanels:CreatePanel(newName)
		if panelId then CooldownPanels:SelectPanel(panelId) end
	end)

	deletePanel:SetScript("OnClick", function()
		local panelId = editor.selectedPanelId
		if not panelId then return end
		local panel = CooldownPanels:GetPanel(panelId)
		ensureDeletePopup()
		StaticPopup_Show("EQOL_COOLDOWN_PANEL_DELETE", panel and panel.name or nil, nil, { panelId = panelId })
	end)

	addSpellBox:SetScript("OnEnterPressed", function(self)
		local panelId = editor.selectedPanelId
		local value = tonumber(self:GetText())
		if panelId and value then CooldownPanels:AddEntrySafe(panelId, "SPELL", value) end
		self:SetText("")
		self:ClearFocus()
		CooldownPanels:RefreshEditor()
	end)

	addItemBox:SetScript("OnEnterPressed", function(self)
		local panelId = editor.selectedPanelId
		local value = tonumber(self:GetText())
		if panelId and value then CooldownPanels:AddEntrySafe(panelId, "ITEM", value) end
		self:SetText("")
		self:ClearFocus()
		CooldownPanels:RefreshEditor()
	end)

	slotTrinket1:SetScript("OnClick", function()
		if editor.selectedPanelId then CooldownPanels:AddEntrySafe(editor.selectedPanelId, "SLOT", 13) end
		CooldownPanels:RefreshEditor()
	end)
	slotTrinket2:SetScript("OnClick", function()
		if editor.selectedPanelId then CooldownPanels:AddEntrySafe(editor.selectedPanelId, "SLOT", 14) end
		CooldownPanels:RefreshEditor()
	end)
	slotMainHand:SetScript("OnClick", function()
		if editor.selectedPanelId then CooldownPanels:AddEntrySafe(editor.selectedPanelId, "SLOT", 16) end
		CooldownPanels:RefreshEditor()
	end)
	slotOffHand:SetScript("OnClick", function()
		if editor.selectedPanelId then CooldownPanels:AddEntrySafe(editor.selectedPanelId, "SLOT", 17) end
		CooldownPanels:RefreshEditor()
	end)

	panelNameBox:SetScript("OnEnterPressed", function(self)
		local panelId = editor.selectedPanelId
		local panel = panelId and CooldownPanels:GetPanel(panelId)
		local text = self:GetText()
		if panel and text and text ~= "" then
			panel.name = text
			CooldownPanels:RefreshPanel(panelId)
			local runtimePanel = CooldownPanels.runtime and CooldownPanels.runtime[panelId]
			if runtimePanel and runtimePanel.editModeId and EditMode and EditMode.RefreshFrame then EditMode:RefreshFrame(runtimePanel.editModeId) end
		end
		self:ClearFocus()
		CooldownPanels:RefreshEditor()
	end)
	panelNameBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		CooldownPanels:RefreshEditor()
	end)

	panelEnabled:SetScript("OnClick", function(self)
		local panelId = editor.selectedPanelId
		local panel = panelId and CooldownPanels:GetPanel(panelId)
		if panel then
			panel.enabled = self:GetChecked() and true or false
			CooldownPanels:RefreshPanel(panelId)
			CooldownPanels:RefreshEditor()
		end
	end)

	entryIdBox:SetScript("OnEnterPressed", function(self)
		local panelId = editor.selectedPanelId
		local entryId = editor.selectedEntryId
		local panel = panelId and CooldownPanels:GetPanel(panelId)
		local entry = panel and panel.entries and panel.entries[entryId]
		local value = tonumber(self:GetText())
		if not panel or not entry or not value then
			self:ClearFocus()
			CooldownPanels:RefreshEditor()
			return
		end
		if entry.type == "SPELL" and not isSpellKnownSafe(value) then
			showErrorMessage(SPELL_FAILED_NOT_KNOWN or "Spell not known.")
			self:ClearFocus()
			CooldownPanels:RefreshEditor()
			return
		end
		local existingId = CooldownPanels:FindEntryByValue(panelId, entry.type, value)
		if existingId and existingId ~= entryId then
			showErrorMessage("Entry already exists.")
			self:ClearFocus()
			CooldownPanels:RefreshEditor()
			return
		end
		if entry.type == "SPELL" then
			entry.spellID = value
		elseif entry.type == "ITEM" then
			entry.itemID = value
		elseif entry.type == "SLOT" then
			entry.slotID = value
		end
		self:ClearFocus()
		CooldownPanels:RefreshPanel(panelId)
		CooldownPanels:RefreshEditor()
	end)
	entryIdBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		CooldownPanels:RefreshEditor()
	end)

	local function bindEntryToggle(cb, field)
		cb:SetScript("OnClick", function(self)
			local panelId = editor.selectedPanelId
			local entryId = editor.selectedEntryId
			local panel = panelId and CooldownPanels:GetPanel(panelId)
			local entry = panel and panel.entries and panel.entries[entryId]
			if not entry then return end
			entry[field] = self:GetChecked() and true or false
			CooldownPanels:RefreshPanel(panelId)
			CooldownPanels:RefreshEditor()
		end)
	end

	bindEntryToggle(cbAlways, "alwaysShow")
	bindEntryToggle(cbCooldown, "showCooldown")
	bindEntryToggle(cbCharges, "showCharges")
	bindEntryToggle(cbStacks, "showStacks")
	bindEntryToggle(cbGlow, "glowReady")

	removeEntry:SetScript("OnClick", function()
		local panelId = editor.selectedPanelId
		local entryId = editor.selectedEntryId
		if panelId and entryId then
			CooldownPanels:RemoveEntry(panelId, entryId)
			editor.selectedEntryId = nil
			CooldownPanels:RefreshEditor()
		end
	end)

	return runtime.editor
end

local function ensureDeletePopup()
	if StaticPopupDialogs["EQOL_COOLDOWN_PANEL_DELETE"] then return end
	StaticPopupDialogs["EQOL_COOLDOWN_PANEL_DELETE"] = {
		text = L["CooldownPanelDeletePanel"] or "Delete Panel?",
		button1 = YES,
		button2 = CANCEL,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
		OnAccept = function(self, data)
			if not data or not data.panelId then return end
			CooldownPanels:DeletePanel(data.panelId)
			CooldownPanels:RefreshEditor()
		end,
	}
end

local function updateRowVisual(row, selected)
	if not row or not row.bg then return end
	if selected then
		row.bg:SetColorTexture(0.1, 0.6, 0.6, 0.35)
	else
		row.bg:SetColorTexture(0, 0, 0, 0.2)
	end
end

local function refreshPanelList(editor, root)
	local list = editor.panelList
	if not list then return end
	local content = list.content
	local rowHeight = 28
	local spacing = 4
	local index = 0

	for _, panelId in ipairs(root.order or {}) do
		local panel = root.panels and root.panels[panelId]
		if panel then
			index = index + 1
			local row = editor.panelRows[index]
			if not row then
				row = createRowButton(content, rowHeight)
				row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
				row.label:SetPoint("LEFT", row, "LEFT", 8, 0)
				row.label:SetTextColor(1, 1, 1, 1)

				row.count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
				row.count:SetPoint("RIGHT", row, "RIGHT", -8, 0)
				editor.panelRows[index] = row
			end
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((index - 1) * (rowHeight + spacing)))
			row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -((index - 1) * (rowHeight + spacing)))

			row.panelId = panelId
			row.label:SetText(panel.name or ("Panel " .. tostring(panelId)))
			local entryCount = panel.order and #panel.order or 0
			row.count:SetText(entryCount)
			row:Show()

			updateRowVisual(row, panelId == editor.selectedPanelId)
			row:SetScript("OnClick", function() CooldownPanels:SelectPanel(panelId) end)
		end
	end

	for i = index + 1, #editor.panelRows do
		editor.panelRows[i]:Hide()
	end

	local totalHeight = index * (rowHeight + spacing)
	content:SetHeight(totalHeight > 1 and totalHeight or 1)
end

local function refreshEntryList(editor, panel)
	local list = editor.entryList
	if not list then return end
	local content = list.content
	local rowHeight = 30
	local spacing = 4
	local index = 0

	if panel and panel.order then
		for _, entryId in ipairs(panel.order or {}) do
			local entry = panel.entries and panel.entries[entryId]
			if entry then
				index = index + 1
				local row = editor.entryRows[index]
				if not row then
					row = createRowButton(content, rowHeight)
					row.icon = row:CreateTexture(nil, "ARTWORK")
					row.icon:SetSize(22, 22)
					row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)

					row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
					row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
					row.label:SetTextColor(1, 1, 1, 1)

					row.kind = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
					row.kind:SetPoint("RIGHT", row, "RIGHT", -6, 0)
					editor.entryRows[index] = row
				end
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((index - 1) * (rowHeight + spacing)))
				row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -((index - 1) * (rowHeight + spacing)))

				row.entryId = entryId
				row.icon:SetTexture(getEntryIcon(entry))
				row.label:SetText(getEntryName(entry))
				row.kind:SetText(entry.type or "")
				row:Show()

				updateRowVisual(row, entryId == editor.selectedEntryId)
				row:SetScript("OnClick", function() CooldownPanels:SelectEntry(entryId) end)
			end
		end
	end

	for i = index + 1, #editor.entryRows do
		editor.entryRows[i]:Hide()
	end

	local totalHeight = index * (rowHeight + spacing)
	content:SetHeight(totalHeight > 1 and totalHeight or 1)
end

local function refreshPreview(editor, panel)
	if not editor.previewFrame then return end
	local preview = editor.previewFrame
	local canvas = preview.canvas or preview
	if not panel then
		applyIconLayout(canvas, DEFAULT_PREVIEW_COUNT, Helper.PANEL_LAYOUT_DEFAULTS)
		canvas:ClearAllPoints()
		canvas:SetPoint("CENTER", preview, "CENTER")
		for i = 1, DEFAULT_PREVIEW_COUNT do
			local icon = canvas.icons[i]
			icon.texture:SetTexture(PREVIEW_ICON)
			icon.entryId = nil
		end
		if preview.dropHint then
			preview.dropHint:SetText(L["CooldownPanelSelectPanel"] or "Select a panel to edit.")
			preview.dropHint:Show()
		end
		return
	end

	local count = getPreviewCount(panel)
	applyIconLayout(canvas, count, panel.layout or Helper.PANEL_LAYOUT_DEFAULTS)
	canvas:ClearAllPoints()
	canvas:SetPoint("CENTER", preview, "CENTER")

	preview.entryByIndex = preview.entryByIndex or {}
	for i = 1, count do
		local entryId = panel.order and panel.order[i]
		local entry = entryId and panel.entries and panel.entries[entryId] or nil
		local icon = canvas.icons[i]
		icon.texture:SetTexture(getEntryIcon(entry))
		icon.entryId = entryId
	end

	if preview.dropHint then
		preview.dropHint:SetText(L["CooldownPanelDropHint"] or "Drop spells or items here")
		preview.dropHint:SetShown((panel.order and #panel.order or 0) == 0)
	end
end

local function refreshInspector(editor, panel, entry)
	local inspector = editor.inspector
	if not inspector then return end

	if panel then
		inspector.panelName:SetText(panel.name or "")
		inspector.panelEnabled:SetChecked(panel.enabled ~= false)
		inspector.panelName:Enable()
		inspector.panelEnabled:Enable()
	else
		inspector.panelName:SetText("")
		inspector.panelName:Disable()
		inspector.panelEnabled:SetChecked(false)
		inspector.panelEnabled:Disable()
	end

	if entry then
		inspector.entryIcon:SetTexture(getEntryIcon(entry))
		inspector.entryName:SetText(getEntryName(entry))
		inspector.entryType:SetText(entry.type or "")
		inspector.entryId:SetText(tostring(entry.spellID or entry.itemID or entry.slotID or ""))

		inspector.cbAlways:SetChecked(entry.alwaysShow and true or false)
		inspector.cbCooldown:SetChecked(entry.showCooldown and true or false)
		inspector.cbCharges:SetChecked(entry.showCharges and true or false)
		inspector.cbStacks:SetChecked(entry.showStacks and true or false)
		inspector.cbGlow:SetChecked(entry.glowReady and true or false)

		inspector.entryId:Enable()
		inspector.cbAlways:Enable()
		inspector.cbCooldown:Enable()
		inspector.cbCharges:Enable()
		inspector.cbStacks:Enable()
		inspector.cbGlow:Enable()
		inspector.removeEntry:Enable()
	else
		inspector.entryIcon:SetTexture(PREVIEW_ICON)
		inspector.entryName:SetText(L["CooldownPanelSelectEntry"] or "Select an entry.")
		inspector.entryType:SetText("")
		inspector.entryId:SetText("")

		inspector.entryId:Disable()
		inspector.cbAlways:SetChecked(false)
		inspector.cbCooldown:SetChecked(false)
		inspector.cbCharges:SetChecked(false)
		inspector.cbStacks:SetChecked(false)
		inspector.cbGlow:SetChecked(false)
		inspector.cbAlways:Disable()
		inspector.cbCooldown:Disable()
		inspector.cbCharges:Disable()
		inspector.cbStacks:Disable()
		inspector.cbGlow:Disable()
		inspector.removeEntry:Disable()
	end
end

function CooldownPanels:RefreshEditor()
	local editor = getEditor()
	if not editor or not editor.frame or not editor.frame:IsShown() then return end
	local root = ensureRoot()
	if not root then return end

	self:NormalizeAll()
	Helper.SyncOrder(root.order, root.panels)

	local panelId = editor.selectedPanelId or root.selectedPanel or (root.order and root.order[1])
	if panelId and (not root.panels or not root.panels[panelId]) then panelId = root.order and root.order[1] or nil end
	editor.selectedPanelId = panelId
	root.selectedPanel = panelId

	local panel = panelId and root.panels and root.panels[panelId] or nil
	if panel then Helper.NormalizePanel(panel, root.defaults) end

	refreshPanelList(editor, root)
	refreshEntryList(editor, panel)
	refreshPreview(editor, panel)

	local panelActive = panel ~= nil
	if editor.deletePanel then
		if panelActive then
			editor.deletePanel:Enable()
		else
			editor.deletePanel:Disable()
		end
	end
	if editor.addSpellBox then
		if panelActive then
			editor.addSpellBox:Enable()
		else
			editor.addSpellBox:Disable()
		end
	end
	if editor.addItemBox then
		if panelActive then
			editor.addItemBox:Enable()
		else
			editor.addItemBox:Disable()
		end
	end
	if editor.slotButtons then
		for _, btn in pairs(editor.slotButtons) do
			if panelActive then
				btn:Enable()
			else
				btn:Disable()
			end
		end
	end

	local entryId = editor.selectedEntryId
	if panel and entryId and not (panel.entries and panel.entries[entryId]) then entryId = nil end
	editor.selectedEntryId = entryId
	local entry = panel and entryId and panel.entries and panel.entries[entryId] or nil
	refreshInspector(editor, panel, entry)
end

function CooldownPanels:OpenEditor()
	local editor = ensureEditor()
	if not editor then return end
	editor.frame:Show()
	self:RefreshEditor()
end

function CooldownPanels:CloseEditor()
	local editor = getEditor()
	if not editor then return end
	editor.frame:Hide()
end

function CooldownPanels:ToggleEditor()
	local editor = getEditor()
	if not editor then
		self:OpenEditor()
		return
	end
	if editor.frame:IsShown() then
		self:CloseEditor()
	else
		self:OpenEditor()
	end
end

function CooldownPanels:IsEditorOpen()
	local editor = getEditor()
	return editor and editor.frame and editor.frame:IsShown()
end

function CooldownPanels:EnsurePanelFrame(panelId)
	local panel = self:GetPanel(panelId)
	if not panel then return nil end
	local runtime = getRuntime(panelId)
	if runtime.frame then return runtime.frame end
	local frame = createPanelFrame(panelId, panel)
	runtime.frame = frame
	self:ApplyPanelPosition(panelId)
	self:ApplyLayout(panelId)
	self:UpdatePreviewIcons(panelId)
	return frame
end

function CooldownPanels:ApplyLayout(panelId, countOverride)
	local panel = self:GetPanel(panelId)
	if not panel then return end
	local runtime = getRuntime(panelId)
	local frame = runtime.frame
	if not frame then return end
	panel.layout = panel.layout or Helper.CopyTableShallow(Helper.PANEL_LAYOUT_DEFAULTS)
	local layout = panel.layout

	local count = countOverride or getPreviewCount(panel)
	applyIconLayout(frame, count, layout)

	frame:SetFrameStrata(normalizeStrata(layout.strata, Helper.PANEL_LAYOUT_DEFAULTS.strata))
	if frame.label then frame.label:SetText(panel.name or "Cooldown Panel") end
end

function CooldownPanels:UpdatePreviewIcons(panelId, countOverride)
	local panel = self:GetPanel(panelId)
	if not panel then return end
	local runtime = getRuntime(panelId)
	local frame = runtime.frame
	if not frame then return end
	local count = countOverride or getPreviewCount(panel)
	ensureIconCount(frame, count)

	for i = 1, count do
		local entryId = panel.order and panel.order[i]
		local entry = entryId and panel.entries and panel.entries[entryId] or nil
		local icon = frame.icons[i]
		icon.texture:SetTexture(getEntryIcon(entry))
		icon.cooldown:Clear()
		icon.count:Hide()
		icon.charges:Hide()
		icon.texture:SetDesaturated(false)
		icon.texture:SetAlpha(1)
		setGlow(icon, false)
	end
end

function CooldownPanels:UpdateRuntimeIcons(panelId)
	local panel = self:GetPanel(panelId)
	if not panel then return end
	local runtime = getRuntime(panelId)
	local frame = runtime.frame
	if not frame then return end

	local visible = runtime.visibleEntries
	if not visible then
		visible = {}
		runtime.visibleEntries = visible
	else
		for i = 1, #visible do
			visible[i] = nil
		end
	end

	local order = panel.order or {}
	for _, entryId in ipairs(order) do
		local entry = panel.entries and panel.entries[entryId]
		if entry then
			local showCooldown = entry.showCooldown ~= false
			local showCharges = entry.showCharges == true
			local showStacks = entry.showStacks == true
			local alwaysShow = entry.alwaysShow ~= false
			local glowReady = entry.glowReady ~= false

			local iconTexture = getEntryIcon(entry)
			local stackCount
			local chargesInfo
			local cooldownStart, cooldownDuration, cooldownEnabled, cooldownRate
			local show = false

			if entry.type == "SPELL" and entry.spellID then
				if IsSpellKnown and not IsSpellKnown(entry.spellID) then
					show = false
				else
					if showCharges and GetSpellChargesInfo then chargesInfo = GetSpellChargesInfo(entry.spellID) end
					if showCooldown or (showCharges and chargesInfo) then
						cooldownStart, cooldownDuration, cooldownEnabled, cooldownRate = getSpellCooldownInfo(entry.spellID)
					end
					if showStacks and GetPlayerAuraBySpellID then
						local aura = GetPlayerAuraBySpellID(entry.spellID)
						if aura and aura.applications and aura.applications > 1 then stackCount = aura.applications end
					end
					show = alwaysShow
					if not show and showCooldown and cooldownEnabled ~= false and isCooldownActive(cooldownStart, cooldownDuration) then show = true end
					if not show and showCharges and chargesInfo and chargesInfo.maxCharges and chargesInfo.currentCharges and chargesInfo.currentCharges < chargesInfo.maxCharges then show = true end
					if not show and showStacks and stackCount then show = true end
				end
			elseif entry.type == "ITEM" and entry.itemID then
				if hasItem(entry.itemID) then
					if showCooldown then
						cooldownStart, cooldownDuration, cooldownEnabled = getItemCooldownInfo(entry.itemID)
					end
					show = alwaysShow
					if not show and showCooldown and cooldownEnabled ~= false and isCooldownActive(cooldownStart, cooldownDuration) then show = true end
				end
			elseif entry.type == "SLOT" and entry.slotID then
				local itemId = GetInventoryItemID and GetInventoryItemID("player", entry.slotID) or nil
				if itemId then
					iconTexture = GetItemIconByID and GetItemIconByID(itemId) or iconTexture
					if showCooldown then
						cooldownStart, cooldownDuration, cooldownEnabled = getItemCooldownInfo(itemId, entry.slotID)
					end
					show = alwaysShow
					if not show and showCooldown and cooldownEnabled ~= false and isCooldownActive(cooldownStart, cooldownDuration) then show = true end
				end
			end

			if show then
				visible[#visible + 1] = {
					icon = iconTexture or PREVIEW_ICON,
					showCooldown = showCooldown,
					showCharges = showCharges,
					showStacks = showStacks,
					glowReady = glowReady,
					stackCount = stackCount,
					chargesInfo = chargesInfo,
					cooldownStart = cooldownStart or 0,
					cooldownDuration = cooldownDuration or 0,
					cooldownEnabled = cooldownEnabled,
					cooldownRate = cooldownRate or 1,
				}
			end
		end
	end

	local count = #visible
	local layoutCount = count > 0 and count or 1
	self:ApplyLayout(panelId, layoutCount)
	ensureIconCount(frame, count)

	for i = 1, count do
		local data = visible[i]
		local icon = frame.icons[i]
		icon.texture:SetTexture(data.icon or PREVIEW_ICON)

		local cooldownStart = data.cooldownStart or 0
		local cooldownDuration = data.cooldownDuration or 0
		local cooldownRate = data.cooldownRate or 1
		local cooldownActive = data.showCooldown and data.cooldownEnabled ~= false and isCooldownActive(cooldownStart, cooldownDuration)

		if data.showCharges and data.chargesInfo and data.chargesInfo.maxCharges and data.chargesInfo.maxCharges > 0 then
			icon.charges:SetText(data.chargesInfo.currentCharges or 0)
			icon.charges:Show()
			if data.showCooldown and data.chargesInfo.currentCharges and data.chargesInfo.currentCharges < data.chargesInfo.maxCharges then
				cooldownStart = data.chargesInfo.cooldownStartTime or cooldownStart
				cooldownDuration = data.chargesInfo.cooldownDuration or cooldownDuration
				cooldownRate = data.chargesInfo.chargeModRate or cooldownRate
				cooldownActive = data.showCooldown and isCooldownActive(cooldownStart, cooldownDuration)
			end
		else
			icon.charges:Hide()
		end

		if data.showCooldown and cooldownActive then
			icon.cooldown:SetCooldown(cooldownStart, cooldownDuration, cooldownRate)
			icon.texture:SetDesaturated(true)
			icon.texture:SetAlpha(0.5)
		else
			icon.cooldown:Clear()
			icon.texture:SetDesaturated(false)
			icon.texture:SetAlpha(1)
		end

		if data.showStacks and data.stackCount then
			icon.count:SetText(data.stackCount)
			icon.count:Show()
		else
			icon.count:Hide()
		end

		if data.glowReady then
			local ready = false
			if data.showCharges and data.chargesInfo and data.chargesInfo.currentCharges then
				ready = data.chargesInfo.currentCharges > 0
			elseif data.showCooldown then
				ready = not cooldownActive
			end
			setGlow(icon, ready)
		else
			setGlow(icon, false)
		end
	end

	for i = count + 1, #frame.icons do
		local icon = frame.icons[i]
		if icon then
			icon.cooldown:Clear()
			icon.count:Hide()
			icon.charges:Hide()
			icon.texture:SetDesaturated(false)
			icon.texture:SetAlpha(1)
			setGlow(icon, false)
		end
	end

	runtime.visibleCount = count
end

function CooldownPanels:ApplyPanelPosition(panelId)
	local panel = self:GetPanel(panelId)
	if not panel then return end
	local runtime = getRuntime(panelId)
	local frame = runtime.frame
	if not frame then return end
	local point = panel.point or "CENTER"
	local x = tonumber(panel.x) or 0
	local y = tonumber(panel.y) or 0
	frame:ClearAllPoints()
	frame:SetPoint(point, UIParent, point, x, y)
end

function CooldownPanels:HandlePositionChanged(panelId, data)
	local panel = self:GetPanel(panelId)
	if not panel or type(data) ~= "table" then return end
	local runtime = getRuntime(panelId)
	if runtime.suspendEditSync then return end
	panel.point = data.point or panel.point or "CENTER"
	if data.x ~= nil then panel.x = data.x end
	if data.y ~= nil then panel.y = data.y end
end

function CooldownPanels:IsInEditMode() return EditMode and EditMode.IsInEditMode and EditMode:IsInEditMode() end

function CooldownPanels:ShouldShowPanel(panelId)
	local panel = self:GetPanel(panelId)
	if not panel or panel.enabled == false then return false end
	if self:IsInEditMode() == true then return true end
	local runtime = getRuntime(panelId)
	return runtime.visibleCount and runtime.visibleCount > 0
end

function CooldownPanels:UpdateVisibility(panelId)
	local runtime = getRuntime(panelId)
	local frame = runtime.frame
	if not frame then return end
	frame:SetShown(self:ShouldShowPanel(panelId))
	self:UpdatePanelMouseState(panelId)
end

function CooldownPanels:UpdatePanelMouseState(panelId)
	local runtime = getRuntime(panelId)
	local frame = runtime.frame
	if not frame then return end
	local enable = self:IsInEditMode() == true
	if frame._mouseEnabled ~= enable then
		frame._mouseEnabled = enable
		frame:EnableMouse(enable)
	end
end

function CooldownPanels:ShowEditModeHint(panelId, show)
	local runtime = getRuntime(panelId)
	local frame = runtime.frame
	if not frame then return end
	if show then
		if frame.bg then frame.bg:Show() end
		if frame.label then frame.label:Show() end
	else
		if frame.bg then frame.bg:Hide() end
		if frame.label then frame.label:Hide() end
	end
end

function CooldownPanels:RefreshPanel(panelId)
	if not self:GetPanel(panelId) then return end
	self:EnsurePanelFrame(panelId)
	if self:IsInEditMode() then
		self:ApplyLayout(panelId)
		self:UpdatePreviewIcons(panelId)
	else
		self:UpdateRuntimeIcons(panelId)
	end
	self:UpdateVisibility(panelId)
end

function CooldownPanels:RefreshAllPanels()
	local root = ensureRoot()
	if not root then return end
	Helper.SyncOrder(root.order, root.panels)
	for _, panelId in ipairs(root.order) do
		self:RefreshPanel(panelId)
	end
	for panelId in pairs(root.panels) do
		if not containsId(root.order, panelId) then self:RefreshPanel(panelId) end
	end
end

local function syncEditModeValue(panelId, field, value)
	local runtime = getRuntime(panelId)
	if not runtime or runtime.applyingFromEditMode then return end
	if runtime.editModeId and EditMode and EditMode.SetValue then EditMode:SetValue(runtime.editModeId, field, value, nil, true) end
end

local function applyEditLayout(panelId, field, value, skipRefresh)
	local panel = CooldownPanels:GetPanel(panelId)
	if not panel then return end
	panel.layout = panel.layout or {}
	local layout = panel.layout

	if field == "iconSize" then
		layout.iconSize = clampInt(value, 12, 128, layout.iconSize)
	elseif field == "spacing" then
		layout.spacing = clampInt(value, 0, 50, layout.spacing)
	elseif field == "direction" then
		layout.direction = normalizeDirection(value, layout.direction)
	elseif field == "wrapCount" then
		layout.wrapCount = clampInt(value, 0, 40, layout.wrapCount)
	elseif field == "wrapDirection" then
		layout.wrapDirection = normalizeDirection(value, layout.wrapDirection)
	elseif field == "strata" then
		layout.strata = normalizeStrata(value, layout.strata)
	end

	syncEditModeValue(panelId, field, layout[field])

	if not skipRefresh then
		CooldownPanels:ApplyLayout(panelId)
		CooldownPanels:UpdatePreviewIcons(panelId)
	end
end

function CooldownPanels:ApplyEditMode(panelId, data)
	local panel = self:GetPanel(panelId)
	if not panel or type(data) ~= "table" then return end
	local runtime = getRuntime(panelId)
	runtime.applyingFromEditMode = true

	applyEditLayout(panelId, "iconSize", data.iconSize, true)
	applyEditLayout(panelId, "spacing", data.spacing, true)
	applyEditLayout(panelId, "direction", data.direction, true)
	applyEditLayout(panelId, "wrapCount", data.wrapCount, true)
	applyEditLayout(panelId, "wrapDirection", data.wrapDirection, true)
	applyEditLayout(panelId, "strata", data.strata, true)

	runtime.applyingFromEditMode = nil
	self:ApplyLayout(panelId)
	self:UpdatePreviewIcons(panelId)
	self:UpdateVisibility(panelId)
	if self:IsEditorOpen() then self:RefreshEditor() end
end

function CooldownPanels:RegisterEditModePanel(panelId)
	local panel = self:GetPanel(panelId)
	if not panel then return end
	local runtime = getRuntime(panelId)
	if runtime.editModeRegistered then
		if runtime.editModeId and EditMode and EditMode.RefreshFrame then EditMode:RefreshFrame(runtime.editModeId) end
		return
	end
	if not EditMode or not EditMode.RegisterFrame then return end

	local frame = self:EnsurePanelFrame(panelId)
	if not frame then return end

	local editModeId = "cooldownPanel:" .. tostring(panelId)
	runtime.editModeId = editModeId

	panel.layout = panel.layout or Helper.CopyTableShallow(Helper.PANEL_LAYOUT_DEFAULTS)
	local layout = panel.layout
	local settings
	if SettingType then
		settings = {
			{
				name = "Icon size",
				kind = SettingType.Slider,
				field = "iconSize",
				default = layout.iconSize,
				minValue = 12,
				maxValue = 128,
				valueStep = 1,
				get = function() return layout.iconSize end,
				set = function(_, value) applyEditLayout(panelId, "iconSize", value) end,
				formatter = function(value) return tostring(math.floor((tonumber(value) or 0) + 0.5)) end,
			},
			{
				name = "Spacing",
				kind = SettingType.Slider,
				field = "spacing",
				default = layout.spacing,
				minValue = 0,
				maxValue = 50,
				valueStep = 1,
				get = function() return layout.spacing end,
				set = function(_, value) applyEditLayout(panelId, "spacing", value) end,
				formatter = function(value) return tostring(math.floor((tonumber(value) or 0) + 0.5)) end,
			},
			{
				name = "Direction",
				kind = SettingType.Dropdown,
				field = "direction",
				height = 120,
				get = function() return normalizeDirection(layout.direction, Helper.PANEL_LAYOUT_DEFAULTS.direction) end,
				set = function(_, value) applyEditLayout(panelId, "direction", value) end,
				generator = function(_, root)
					for _, option in ipairs(directionOptions) do
						root:CreateRadio(
							option.label,
							function() return normalizeDirection(layout.direction, Helper.PANEL_LAYOUT_DEFAULTS.direction) == option.value end,
							function() applyEditLayout(panelId, "direction", option.value) end
						)
					end
				end,
			},
			{
				name = "Wrap",
				kind = SettingType.Slider,
				field = "wrapCount",
				default = layout.wrapCount or 0,
				minValue = 0,
				maxValue = 40,
				valueStep = 1,
				get = function() return layout.wrapCount or 0 end,
				set = function(_, value) applyEditLayout(panelId, "wrapCount", value) end,
				formatter = function(value) return tostring(math.floor((tonumber(value) or 0) + 0.5)) end,
			},
			{
				name = "Wrap direction",
				kind = SettingType.Dropdown,
				field = "wrapDirection",
				height = 120,
				get = function() return normalizeDirection(layout.wrapDirection, Helper.PANEL_LAYOUT_DEFAULTS.wrapDirection or "DOWN") end,
				set = function(_, value) applyEditLayout(panelId, "wrapDirection", value) end,
				generator = function(_, root)
					for _, option in ipairs(directionOptions) do
						root:CreateRadio(
							option.label,
							function() return normalizeDirection(layout.wrapDirection, Helper.PANEL_LAYOUT_DEFAULTS.wrapDirection or "DOWN") == option.value end,
							function() applyEditLayout(panelId, "wrapDirection", option.value) end
						)
					end
				end,
			},
			{
				name = "Strata",
				kind = SettingType.Dropdown,
				field = "strata",
				height = 200,
				get = function() return normalizeStrata(layout.strata, Helper.PANEL_LAYOUT_DEFAULTS.strata) end,
				set = function(_, value) applyEditLayout(panelId, "strata", value) end,
				generator = function(_, root)
					for _, option in ipairs(STRATA_ORDER) do
						root:CreateRadio(
							option,
							function() return normalizeStrata(layout.strata, Helper.PANEL_LAYOUT_DEFAULTS.strata) == option end,
							function() applyEditLayout(panelId, "strata", option) end
						)
					end
				end,
			},
		}
	end

	EditMode:RegisterFrame(editModeId, {
		frame = frame,
		title = panel.name or "Cooldown Panel",
		layoutDefaults = {
			point = panel.point or "CENTER",
			relativePoint = panel.point or "CENTER",
			x = panel.x or 0,
			y = panel.y or 0,
			iconSize = layout.iconSize,
			spacing = layout.spacing,
			direction = normalizeDirection(layout.direction, Helper.PANEL_LAYOUT_DEFAULTS.direction),
			wrapCount = layout.wrapCount or 0,
			wrapDirection = normalizeDirection(layout.wrapDirection, Helper.PANEL_LAYOUT_DEFAULTS.wrapDirection or "DOWN"),
			strata = normalizeStrata(layout.strata, Helper.PANEL_LAYOUT_DEFAULTS.strata),
		},
		onApply = function(_, _, data) self:ApplyEditMode(panelId, data) end,
		onPositionChanged = function(_, _, data) self:HandlePositionChanged(panelId, data) end,
		onEnter = function() self:ShowEditModeHint(panelId, true) end,
		onExit = function() self:ShowEditModeHint(panelId, false) end,
		isEnabled = function() return panel.enabled ~= false end,
		settings = settings,
		showOutsideEditMode = true,
	})

	runtime.editModeRegistered = true
	self:UpdateVisibility(panelId)
end

function CooldownPanels:EnsureEditMode()
	local root = ensureRoot()
	if not root then return end
	Helper.SyncOrder(root.order, root.panels)
	for _, panelId in ipairs(root.order) do
		self:RegisterEditModePanel(panelId)
	end
	for panelId in pairs(root.panels) do
		if not containsId(root.order, panelId) then self:RegisterEditModePanel(panelId) end
	end
end

local editModeCallbacksRegistered = false
local function registerEditModeCallbacks()
	if editModeCallbacksRegistered then return end
	if addon.EditModeLib and addon.EditModeLib.RegisterCallback then
		addon.EditModeLib:RegisterCallback("enter", function() CooldownPanels:RefreshAllPanels() end)
		addon.EditModeLib:RegisterCallback("exit", function() CooldownPanels:RefreshAllPanels() end)
	end
	editModeCallbacksRegistered = true
end

local function ensureUpdateFrame()
	if CooldownPanels.runtime and CooldownPanels.runtime.updateFrame then return end
	local frame = CreateFrame("Frame")
	frame:SetScript("OnEvent", function(_, event, ...)
		if event == "UNIT_AURA" then
			local unit = ...
			if unit ~= "player" then return end
		end
		CooldownPanels:RequestUpdate()
	end)
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	frame:RegisterEvent("SPELL_UPDATE_CHARGES")
	frame:RegisterEvent("SPELLS_CHANGED")
	frame:RegisterEvent("UNIT_AURA")
	frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	frame:RegisterEvent("BAG_UPDATE_DELAYED")
	frame:RegisterEvent("BAG_UPDATE_COOLDOWN")
	frame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
	CooldownPanels.runtime = CooldownPanels.runtime or {}
	CooldownPanels.runtime.updateFrame = frame
end

function CooldownPanels:RequestUpdate()
	self.runtime = self.runtime or {}
	if self.runtime.updatePending then return end
	self.runtime.updatePending = true
	C_Timer.After(0, function()
		self.runtime.updatePending = nil
		CooldownPanels:RefreshAllPanels()
	end)
end

function CooldownPanels:Init()
	self:NormalizeAll()
	self:EnsureEditMode()
	self:RefreshAllPanels()
	ensureUpdateFrame()
	registerEditModeCallbacks()
end

function addon.Aura.functions.InitCooldownPanels()
	if CooldownPanels and CooldownPanels.Init then CooldownPanels:Init() end
end
