local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.ChatIcons = addon.ChatIcons or {}
local ChatIcons = addon.ChatIcons

local ICON_SIZE = 12
local CURRENCY_LINK_PATTERN = "(|Hcurrency:(%d+)[^|]*|h%[[^%]]+%]|h%|r)"
local ITEM_LINK_PATTERN = "|Hitem:.-|h%[.-%]|h|r"

local tonumber = tonumber
local format = string.format

local function GetItemTexture(link)
	if not link then return nil end

	if GetItemIcon then
		local ok, texture = pcall(GetItemIcon, link)
		if ok and texture then return texture end
	end

	if C_Item and C_Item.GetItemIconByID then
		local itemID = link:match("item:(%d+)")
		if itemID then return C_Item.GetItemIconByID(tonumber(itemID)) end
	end

	return nil
end

local function AppendIcon(texture, link)
	if not texture then return link end
	return format("|T%s:%d|t%s", texture, ICON_SIZE, link)
end

local function FormatItemLink(link)
	return AppendIcon(GetItemTexture(link), link)
end

local function FormatCurrencyLink(link, id)
	id = tonumber(id)
	if not id then return link end
	if not C_CurrencyInfo or not C_CurrencyInfo.GetCurrencyInfo then return link end

	local info = C_CurrencyInfo.GetCurrencyInfo(id)
	local texture = info and (info.iconFileID or info.icon)
	return AppendIcon(texture, link)
end

local function FilterChatMessage(_, event, message, ...)
	if type(message) ~= "string" or message == "" then return false end

	if event == "CHAT_MSG_LOOT" then message = message:gsub(ITEM_LINK_PATTERN, FormatItemLink) end
	if event == "CHAT_MSG_LOOT" or event == "CHAT_MSG_CURRENCY" then message = message:gsub(CURRENCY_LINK_PATTERN, FormatCurrencyLink) end

	return false, message, ...
end

ChatIcons.Filter = ChatIcons.Filter or FilterChatMessage
ChatIcons.enabled = ChatIcons.enabled or false

function ChatIcons:SetEnabled(enabled)
	if enabled and not self.enabled then
		ChatFrame_AddMessageEventFilter("CHAT_MSG_LOOT", self.Filter)
		ChatFrame_AddMessageEventFilter("CHAT_MSG_CURRENCY", self.Filter)
		self.enabled = true
	elseif not enabled and self.enabled then
		ChatFrame_RemoveMessageEventFilter("CHAT_MSG_LOOT", self.Filter)
		ChatFrame_RemoveMessageEventFilter("CHAT_MSG_CURRENCY", self.Filter)
		self.enabled = false
	end
end

