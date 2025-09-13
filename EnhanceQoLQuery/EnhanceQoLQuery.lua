local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

-- Event frame (no visible UI)
local eventFrame = CreateFrame("Frame")
local AceGUI = LibStub and LibStub("AceGUI-3.0", true)

addon.Query = addon.Query or {}
addon.Query.ui = addon.Query.ui or {}

local currentMode = "drink" -- one of: "drink", "potion", "auto"
local reSearchList = {}
local resultsAHSearch = {}
local lastProcessedBrowseCount = 0
local browseStallCount = 0
local executeSearch = false
local loadedResults = {}

local function setMode(mode)
    currentMode = mode
    local titleSuffix = (mode == "drink" and "Drinks") or (mode == "potion" and "Mana Potions") or "Auto"
    if addon.Query.ui and addon.Query.ui.window then addon.Query.ui.window:SetTitle("EnhanceQoLQuery - " .. titleSuffix) end
    if addon.Query.ui and addon.Query.ui.scanBtn then addon.Query.ui.scanBtn:SetText(mode == "potion" and "Scan Potions" or "Scan Drinks") end
end

local addedItems = {} -- known items already present in code lists
local inputAdded = {} -- items the user has added in the current input session
local addedResults = {}

local function seedKnownItems()
    wipe(addedItems)
    if addon and addon.Drinks and addon.Drinks.drinkList then
        for _, drink in ipairs(addon.Drinks.drinkList) do
            if drink and drink.id then addedItems[tostring(drink.id)] = true end
        end
    end
    if addon and addon.Drinks and addon.Drinks.manaPotions then
        for _, pot in ipairs(addon.Drinks.manaPotions) do
            if pot and pot.id then addedItems[tostring(pot.id)] = true end
        end
    end
end

local tooltip = CreateFrame("GameTooltip", "EnhanceQoLQueryTooltip", UIParent, "GameTooltipTemplate")

local function extractManaFromTooltip(itemLink)
    tooltip:SetOwner(UIParent, "ANCHOR_NONE")
    tooltip:SetHyperlink(itemLink)
    local mana = 0

    for i = 1, tooltip:NumLines() do
        local text = _G["EnhanceQoLQueryTooltipTextLeft" .. i]:GetText()
        if text and text:lower():find("mana") then
            -- Prefer explicit "million mana" match to avoid picking up unrelated "million" (e.g., health)
            local millionStr = text:lower():match("([%d%.,]+)%s*million%s*mana")
            if millionStr then
                local clean = (millionStr:gsub(",", "")) -- keep decimal dot for fractional millions
                local v = tonumber(clean) or 0
                mana = math.floor(v * 1000000 + 0.5)
                break
            end
            -- Fallback: plain numeric before "mana" (supports thousands separators)
            local plainStr = text:match("([%d%.,]+)%s*mana")
            if plainStr then
                local clean = plainStr:gsub("[,%.]", "")
                mana = tonumber(clean) or 0
                break
            end
        end
    end

    tooltip:Hide()
    return mana
end

local function extractWellFedFromTooltip(itemLink)
	tooltip:SetOwner(UIParent, "ANCHOR_NONE")
	tooltip:SetHyperlink(itemLink)
	local buffFood = "false"

	for i = 1, tooltip:NumLines() do
		local text = _G["EnhanceQoLQueryTooltipTextLeft" .. i]:GetText()
		if text and (text:match("well fed") or text:match("Well Fed")) then
			buffFood = "true"
			break
		end
	end

	tooltip:Hide()
	return buffFood
end

local function classifyItemByIDs(itemID)
    if not itemID then return nil end
    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    if classID == Enum.ItemClass.Consumable then
        if subClassID == Enum.ItemConsumableSubclass.Fooddrink then return "drink" end
        if subClassID == Enum.ItemConsumableSubclass.Potion then return "potion" end
    end
    if classID == Enum.ItemClass.Gem then return "gem" end
    return nil
end

local function sanitizeKey(name)
    local formatted = tostring(name or "")
    -- Remove quotes and collapse spaces to avoid invalid Lua string keys
    formatted = formatted:gsub('"', "")
    formatted = formatted:gsub("'", "")
    formatted = formatted:gsub("%s+", "")
    -- Fallback if empty after sanitization
    if formatted == "" then formatted = "item" end
    return formatted
end

-- Pretty text for item quality
local function qualityText(q)
    local n = tonumber(q) or 0
    local names = {
        [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic",
        [5] = "Legendary", [6] = "Artifact", [7] = "Heirloom", [8] = "WoWToken",
    }
    return string.format("%s (%d)", names[n] or tostring(n), n)
end

-- Public inspector function used by AceUI and Shift+Click when in inspector
function addon.Query.showItem(itemLink)
    local itemName, itemLink2, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType,
        itemStackCount, itemEquipLoc, itemTexture, sellPrice, classID, subclassID,
        bindType, expansionID, setID, isCraftingReagent = C_Item.GetItemInfo(itemLink)

    local function coinText(c)
        c = tonumber(c or 0) or 0
        if c <= 0 then return "0c" end
        local g = math.floor(c / 10000)
        local s = math.floor((c % 10000) / 100)
        local k = c % 100
        local parts = {}
        if g > 0 then table.insert(parts, g .. "g") end
        if s > 0 then table.insert(parts, s .. "s") end
        if k > 0 then table.insert(parts, k .. "c") end
        return table.concat(parts, " ")
    end

    local BIND_NAMES = { [0] = "None", [1] = "Bind on Pickup", [2] = "Bind on Equip", [3] = "Bind on Use", [4] = "Quest" }
    local function expansionName(id)
        if id == nil then return nil end
        local key = "EXPANSION_NAME" .. tostring(id)
        return _G[key] or nil
    end

    local lines = {}
    local function addRaw(key, val)
        if val ~= nil then table.insert(lines, string.format("%s: %s", key, tostring(val))) end
    end
    local function addFriendly(key, friendly, raw)
        if friendly ~= nil then table.insert(lines, string.format("%s: %s", key, tostring(friendly))) end
        if raw ~= nil then table.insert(lines, string.format("%s (raw): %s", key, tostring(raw))) end
    end

    -- Name/link
    addRaw("itemName", itemName)
    addRaw("itemLink", itemLink2)

    -- Quality combined
    if itemQuality ~= nil then addFriendly("itemQuality", qualityText(itemQuality), itemQuality) end

    -- Levels
    addRaw("itemLevel", itemLevel)
    addRaw("itemMinLevel", itemMinLevel)

    -- Types
    addRaw("itemType", itemType)
    addRaw("itemSubType", itemSubType)
    addRaw("itemStackCount", itemStackCount)

    -- Equip location: show localized name if possible
    if itemEquipLoc ~= nil then
        local locName = _G[itemEquipLoc]
        if locName and locName ~= "" then
            addFriendly("itemEquipLoc", string.format("%s (%s)", itemEquipLoc, locName), itemEquipLoc)
        else
            addRaw("itemEquipLoc", itemEquipLoc)
        end
    end

    -- Texture fileID
    addRaw("itemTexture", itemTexture)

    -- Sell price: raw and gold/silver/copper
    if sellPrice ~= nil then addFriendly("sellPrice", coinText(sellPrice), sellPrice) end

    -- Class/subclass raw (names already shown by type/subtype)
    addRaw("classID", classID)
    addRaw("subclassID", subclassID)

    -- Bind type friendly + raw
    if bindType ~= nil then addFriendly("bindType", BIND_NAMES[bindType] or tostring(bindType), bindType) end

    -- Expansion friendly + raw
    if expansionID ~= nil then addFriendly("expansionID", expansionName(expansionID) or tostring(expansionID), expansionID) end

    -- Set / crafting reagent
    addRaw("setID", setID)
    if isCraftingReagent ~= nil then addRaw("isCraftingReagent", isCraftingReagent) end

    if addon.Query.ui and addon.Query.ui.inspectorOutput then addon.Query.ui.inspectorOutput:SetText(table.concat(lines, "\n")) end
end

local function formatDrinkString(name, itemID, minLevel, mana, isBuffFood)
    local formattedKey = sanitizeKey(name) ~= "" and sanitizeKey(name) or ("item" .. tostring(itemID))
    return string.format('{ key = "%s", id = %d, requiredLevel = %d, mana = %d, isBuffFood = %s }', formattedKey, itemID, minLevel or 1, mana or 0, tostring(isBuffFood))
end

local function formatGemDrinkString(name, itemID, minLevel, mana, isBuffFood)
    local formattedKey = sanitizeKey(name) ~= "" and sanitizeKey(name) or ("item" .. tostring(itemID))
    return string.format('{ key = "%s", id = %d, requiredLevel = %d, mana = %d, isBuffFood = %s, isEarthenFood = true, earthenOnly = true }', formattedKey, itemID, minLevel or 1, mana or 0, tostring(isBuffFood))
end

local function formatPotionString(name, itemID, minLevel, mana)
    local formattedKey = sanitizeKey(name) ~= "" and sanitizeKey(name) or ("item" .. tostring(itemID))
    return string.format('{ key = "%s", id = %d, requiredLevel = %d, mana = %d }', formattedKey, itemID, minLevel or 1, mana or 0)
end

local function updateItemInfo(itemLink)
	if not itemLink then return end
	local name, link, quality, level, minLevel, type, subType, stackCount, equipLoc, texture = C_Item.GetItemInfo(itemLink)
	local mana = extractManaFromTooltip(itemLink)
	if name and type and subType and minLevel and mana > 0 then
		local itemID = tonumber(itemLink:match("item:(%d+)"))
		local kind = currentMode
		if kind == "auto" then kind = classifyItemByIDs(itemID) or "drink" end
		if kind == "potion" then
			return formatPotionString(name, itemID, minLevel, mana)
		else
			local buffFood = extractWellFedFromTooltip(itemLink)
			if type == "Gem" then
				return formatGemDrinkString(name, itemID, minLevel, mana, buffFood)
			else
				return formatDrinkString(name, itemID, minLevel, mana, buffFood)
			end
		end
	end
	return nil
end

-- Output helper + input processing (AceGUI path)
local function UI_SetOutput(text)
    if addon.Query.ui and addon.Query.ui.output then addon.Query.ui.output:SetText(text or "") end
end

local function processInputText(text)
    local itemLinks = { strsplit(" ", text or "") }
    local results = {}
    for _, itemLink in ipairs(itemLinks) do
        local itemID = itemLink:match("item:(%d+)")
        if itemID then
            local result = loadedResults[itemID]
            if result == nil then
                result = updateItemInfo(itemLink)
                loadedResults[itemID] = result
            end
            if result then table.insert(results, result) end
        end
    end
    UI_SetOutput(table.concat(results, ",\n        "))
end

-- (legacy editbox removed; AceGUI input handles text changes)


local function addToSearchResult(itemID)
	local name, link, quality, level, minLevel, type, subType = C_Item.GetItemInfo(itemID)
	if not link then return end
	local mana = extractManaFromTooltip(link)
	if not (name and type and subType and minLevel and mana > 0) then return end
	local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
	local result
	if currentMode == "potion" then
		if classID == Enum.ItemClass.Consumable and subClassID == Enum.ItemConsumableSubclass.Potion then
			result = formatPotionString(name, itemID, minLevel, mana)
		end
	else
		if classID == Enum.ItemClass.Consumable and subClassID == Enum.ItemConsumableSubclass.Fooddrink then
			local buffFood = extractWellFedFromTooltip(link)
			result = formatDrinkString(name, itemID, minLevel, mana, buffFood)
		end
	end
	-- Skip items already in our master lists or already added in this session
	if result and not addedItems[tostring(itemID)] and not addedResults[tostring(itemID)] then
		addedResults[tostring(itemID)] = true
		table.insert(resultsAHSearch, result)
	end
    UI_SetOutput(table.concat(resultsAHSearch, ",\n        "))
end

local function handleItemLink(text)
	local name, link, quality, level, minLevel, type, subType, stackCount, equipLoc, texture = C_Item.GetItemInfo(text)
	local itemID = text and text:match("item:(%d+)") and tonumber(text:match("item:(%d+)")) or nil
	local kind = currentMode
	if kind == "auto" then kind = classifyItemByIDs(itemID) or "drink" end
	local isDrink = (type == "Consumable" and subType == "Food & Drink") or (type == "Gem" and select(2, UnitRace("player")) == "EarthenDwarf")
	local isPotion = (type == "Consumable" and subType == "Potion")
    if (kind == "drink" and isDrink) or (kind == "potion" and isPotion) or (kind == "drink" and type == "Gem") then
        local itemId = text:match("item:(%d+)")
        if not inputAdded[itemId] then
            inputAdded[itemId] = true
            if addon.Query.ui and addon.Query.ui.input then
                local currentText = addon.Query.ui.input:GetText() or ""
                addon.Query.ui.input:SetText((currentText ~= "" and (currentText .. " ") or "") .. text)
            end
        else
            print("Item is already in the list.")
        end
	else
		print("Item not matching mode or not supported.")
	end
end

local function BuildAceWindow()
    if not AceGUI then return end
    if addon.Query.ui and addon.Query.ui.window then return end
    local win = AceGUI:Create("Window")
    addon.Query.ui = addon.Query.ui or {}
    addon.Query.ui.window = win
    win:SetTitle("EnhanceQoLQuery - Drinks")
    win:SetWidth(700)
    win:SetHeight(520)
    win:SetLayout("Fill")

    local tree = AceGUI:Create("TreeGroup")
    addon.Query.ui.tree = tree
    tree:SetTree({ { value = "generator", text = "Generator" }, { value = "inspector", text = "GetItemInfo" } })
    tree:SetLayout("Fill")
    win:AddChild(tree)

    local function buildGenerator(container)
        addon.Query.ui.activeGroup = "generator"
        container:ReleaseChildren()
        local outer = AceGUI:Create("SimpleGroup"); outer:SetFullWidth(true); outer:SetFullHeight(true); outer:SetLayout("List"); container:AddChild(outer)

        local row = AceGUI:Create("SimpleGroup"); row:SetFullWidth(true); row:SetLayout("Flow"); outer:AddChild(row)
        local lbl = AceGUI:Create("Label"); lbl:SetText("Mode:"); lbl:SetWidth(60); row:AddChild(lbl)
        local b1 = AceGUI:Create("Button"); b1:SetText("Drinks"); b1:SetWidth(100); b1:SetCallback("OnClick", function() setMode("drink") end); row:AddChild(b1)
        local b2 = AceGUI:Create("Button"); b2:SetText("Mana Potions"); b2:SetWidth(120); b2:SetCallback("OnClick", function() setMode("potion") end); row:AddChild(b2)
        local b3 = AceGUI:Create("Button"); b3:SetText("Auto"); b3:SetWidth(80); b3:SetCallback("OnClick", function() setMode("auto") end); row:AddChild(b3)

        local input = AceGUI:Create("MultiLineEditBox"); input:SetLabel("Input (paste item links/IDs; Shift+Click adds here)"); input:SetFullWidth(true); input:SetNumLines(3); input:DisableButton(true); input:SetCallback("OnTextChanged", function(_,_,t) processInputText(t) end); outer:AddChild(input); addon.Query.ui.input = input
        local output = AceGUI:Create("MultiLineEditBox"); output:SetLabel("Generated table rows"); output:SetFullWidth(true); output:SetNumLines(16); output:DisableButton(true); outer:AddChild(output); addon.Query.ui.output = output

        local bottom = AceGUI:Create("SimpleGroup"); bottom:SetFullWidth(true); bottom:SetLayout("Flow"); outer:AddChild(bottom)
        local scanBtn = AceGUI:Create("Button"); scanBtn:SetText("Scan Drinks"); scanBtn:SetWidth(140); scanBtn:SetCallback("OnClick", function()
            executeSearch = true; lastProcessedBrowseCount = 0; browseStallCount = 0
            if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
                local query
                if currentMode == "potion" then
                    query = { searchString = "", sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Name, reverseSort = true } }, filters = { Enum.AuctionHouseFilter.Potions }, itemClassFilters = { { classID = Enum.ItemClass.Consumable, subClassID = Enum.ItemConsumableSubclass.Potion } } }
                else
                    query = { searchString = "", sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Name, reverseSort = true } }, itemClassFilters = { { classID = Enum.ItemClass.Consumable, subClassID = Enum.ItemConsumableSubclass.Fooddrink } } }
                end
                reSearchList = {}; resultsAHSearch = {}; addedResults = {}; C_AuctionHouse.SendBrowseQuery(query)
            else
                print("Auction House is not open.")
            end
        end); bottom:AddChild(scanBtn); addon.Query.ui.scanBtn = scanBtn
        local clearBtn = AceGUI:Create("Button"); clearBtn:SetText("Clear"); clearBtn:SetWidth(120); clearBtn:SetCallback("OnClick", function() input:SetText(""); output:SetText(""); addedResults = {}; resultsAHSearch = {}; inputAdded = {}; wipe(loadedResults) end); bottom:AddChild(clearBtn)
        local copyBtn = AceGUI:Create("Button"); copyBtn:SetText("Copy"); copyBtn:SetWidth(120); copyBtn:SetCallback("OnClick", function() output:SetFocus(); output:HighlightText(); C_Timer.After(0.8, function() output:ClearFocus() end) end); bottom:AddChild(copyBtn)
    end

    local function buildInspector(container)
        addon.Query.ui.activeGroup = "inspector"
        container:ReleaseChildren()
        local outer = AceGUI:Create("SimpleGroup"); outer:SetFullWidth(true); outer:SetFullHeight(true); outer:SetLayout("List"); container:AddChild(outer)
        local tip = AceGUI:Create("Label"); tip:SetText("Shift+Click an item link or use the cursor button to inspect via GetItemInfo()."); tip:SetFullWidth(true); outer:AddChild(tip)
        local pick = AceGUI:Create("Button"); pick:SetText("Load item from cursor"); pick:SetWidth(200); pick:SetCallback("OnClick", function() local t,_,link = GetCursorInfo(); if t=="item" and link then addon.Query.showItem(link); ClearCursor() end end); outer:AddChild(pick)
        local output = AceGUI:Create("MultiLineEditBox"); output:SetLabel("GetItemInfo"); output:SetFullWidth(true); output:SetNumLines(18); output:DisableButton(true); outer:AddChild(output); addon.Query.ui.inspectorOutput = output
        local follow = AceGUI:Create("CheckBox"); follow:SetLabel("Enable follow-up calls (experimental)"); addon.functions.InitDBValue("queryFollowupEnabled", false); follow:SetValue(addon.db.queryFollowupEnabled); follow:SetCallback("OnValueChanged", function(_,_,v) addon.db.queryFollowupEnabled = v and true or false end); outer:AddChild(follow)
    end

    tree:SetCallback("OnGroupSelected", function(_, _, group) if group=="generator" then buildGenerator(tree) else buildInspector(tree) end end)
    tree:SelectByValue("generator")
    setMode(currentMode)
end

local function onAddonLoaded(event, addonName)
    if addonName == "EnhanceQoLQuery" then
        -- Registriere den Slash-Command für /rq
        SLASH_EnhanceQoLQUERY1 = "/rq"
        SlashCmdList["EnhanceQoLQUERY"] = function(msg)
            if not (addon.Query.ui and addon.Query.ui.window) then BuildAceWindow() end
            if addon.Query.ui and addon.Query.ui.window then addon.Query.ui.window:Show() end
        end

        print("EnhanceQoLQuery command registered: /rq")
    end
end

local function onItemPush(bag, slot)
	if nil == bag or nil == slot then return end
	if bag < 0 or bag > 5 or slot < 1 or slot > C_Container.GetContainerNumSlots(bag) then return end
	local itemLink = C_Container.GetContainerItemLink(bag, slot)
	if itemLink then handleItemLink(itemLink) end
end

local function onAuctionHouseEvent(self, event, ...)
	if executeSearch then
		if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
			local browseResults = C_AuctionHouse.GetBrowseResults() or {}
			-- process only new entries since last event to avoid duplicates
			local currentCount = #browseResults
			if currentCount > lastProcessedBrowseCount then
				for i = lastProcessedBrowseCount + 1, currentCount do
					local itemID = browseResults[i] and browseResults[i].itemKey and browseResults[i].itemKey.itemID
					if itemID then
						local _, link = C_Item.GetItemInfo(itemID)
						if nil == link then
							reSearchList[itemID] = true
						else
							addToSearchResult(itemID)
						end
					end
				end
				lastProcessedBrowseCount = currentCount
				browseStallCount = 0
				-- attempt to request more pages if API available
				if C_AuctionHouse.RequestMoreBrowseResults then C_AuctionHouse.RequestMoreBrowseResults() end
			else
				-- No growth, count stalls; stop after a couple of no-growth events
				browseStallCount = (browseStallCount or 0) + 1
				if browseStallCount >= 2 then
					executeSearch = false
					lastProcessedBrowseCount = 0
					browseStallCount = 0
				end
			end
		end
	end
end

local function onGetItemInfoReceived(...)
	local itemID, success = ...
	if success == true and reSearchList[itemID] == true then addToSearchResult(itemID) end
end

local function onEvent(self, event, ...)
	if event == "ADDON_LOADED" then
		-- Ensure slash command is registered as soon as the addon loads
    onAddonLoaded(event, ...)
    seedKnownItems()
	elseif event == "PLAYER_LOGIN" then
		-- Fallback: also register slash on login and seed known items
    onAddonLoaded(event, "EnhanceQoLQuery")
    seedKnownItems()
    elseif event == "ITEM_PUSH" and (addon.Query.ui and addon.Query.ui.window and addon.Query.ui.window.frame and addon.Query.ui.window.frame:IsShown()) then
        onItemPush(...)
    elseif event == "GET_ITEM_INFO_RECEIVED" and (addon.Query.ui and addon.Query.ui.window and addon.Query.ui.window.frame and addon.Query.ui.window.frame:IsShown()) then
        onGetItemInfoReceived(...)
    elseif (addon.Query.ui and addon.Query.ui.window and addon.Query.ui.window.frame and addon.Query.ui.window.frame:IsShown()) then
        onAuctionHouseEvent(self, event, ...)
	end
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("ITEM_PUSH")
eventFrame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
eventFrame:SetScript("OnEvent", onEvent)

-- Handling Shift+Click to add item link to the EditBox and clear previous item
hooksecurefunc("ChatEdit_InsertLink", function(itemLink)
    local shown = (addon.Query.ui and addon.Query.ui.window and addon.Query.ui.window.frame and addon.Query.ui.window.frame:IsShown())
    if itemLink and shown then
        if addon.Query.ui and addon.Query.ui.activeGroup == "inspector" and addon.Query.showItem then
            addon.Query.showItem(itemLink)
        else
            handleItemLink(itemLink)
        end
        return true
    end
end)

-- Legacy UI removed; AceGUI builds UI on demand via /rq
addon.Query.frame = eventFrame
