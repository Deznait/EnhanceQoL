-- luacheck: globals EnhanceQoL INVSLOT_HEAD INVSLOT_SHOULDER INVSLOT_CHEST INVSLOT_WAIST INVSLOT_LEGS INVSLOT_FEET INVSLOT_WRIST INVSLOT_HAND INVSLOT_BACK INVSLOT_MAINHAND INVSLOT_OFFHAND HEADSLOT SHOULDERSLOT CHESTSLOT WAISTSLOT LEGSLOT FEETSLOT WRISTSLOT HANDSSLOT BACKSLOT MAINHANDSLOT SECONDARYHANDSLOT
local addonName, addon = ...
local floor = math.floor
local GetInventoryItemDurability = GetInventoryItemDurability

local itemSlots = {
	[1] = INVTYPE_HEAD,
	[2] = INVTYPE_NECK,
	[3] = INVTYPE_SHOULDER,
	[15] = INVTYPE_CLOAK,
	[5] = INVTYPE_CHEST,
	[9] = INVTYPE_WRIST,
	[10] = INVTYPE_HAND,
	[6] = INVTYPE_WAIST,
	[7] = INVTYPE_LEGS,
	[8] = INVTYPE_FEET,
	[11] = INVTYPE_FINGER,
	[12] = INVTYPE_FINGER,
	[13] = INVTYPE_TRINKET,
	[14] = INVTYPE_TRINKET,
	[16] = INVTYPE_WEAPONMAINHAND,
	[17] = INVTYPE_WEAPONOFFHAND,
}

local function getPercentColor(percent)
	local color
	if tonumber(string.format("%." .. 0 .. "f", percent)) > 80 then
		color = "00FF00"
	elseif tonumber(string.format("%." .. 0 .. "f", percent)) > 50 then
		color = "FFFF00"
	else
		color = "FF0000"
	end
	return color
end

-- Feste Reihenfolge für den Tooltip (anpassen, wenn du willst)
local slotOrder = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17 } -- Head, Neck, Shoulder, Cloak, ...

local function calculateDurability(stream)
	local maxDur, currentDura, critDura = 0, 0, 0
	local lines = {}

	for _, slot in ipairs(slotOrder) do
		local name = itemSlots[slot]
		local cur, max = GetInventoryItemDurability(slot)
		if cur and max and max > 0 then
			local fDur = floor((cur / max) * 100 + 0.5)
			maxDur = maxDur + max
			currentDura = currentDura + cur
			if fDur < 50 then critDura = critDura + 1 end
			lines[#lines + 1] = string.format("%s: |cff%s%d|r%%", name, getPercentColor(fDur), fDur)
		end
	end

	if maxDur == 0 then
		maxDur, currentDura = 100, 100 -- 100% anzeigen, wenn nichts messbar ist
	end

	local durValue = (currentDura / maxDur) * 100
	local color = getPercentColor(durValue)
	local tooltipData = table.concat(lines, "\n")

	local critDuraText = ""
	if critDura > 0 then critDuraText = "|cffff0000" .. critDura .. "|r " .. ITEMS .. " < 50%"end
	EnhanceQoL.DataHub:Publish(stream, {
		text = ("|T136241:16|t |cff%s%.0f|r%% %s"):format(color, durValue, critDuraText),
		tooltip = tooltipData,
	})
end

local provider = {
	id = "durability",
	version = 1,
	title = "Durability",
	events = {
		GUILDBANK_UPDATE_MONEY = function(stream) calculateDurability(stream) end,
		PLAYER_DEAD = function(stream)
			C_Timer.After(1, function() calculateDurability(stream) end)
		end,
		PLAYER_EQUIPMENT_CHANGED = function(stream) calculateDurability(stream) end,
		PLAYER_MONEY = function(stream) calculateDurability(stream) end,
		PLAYER_REGEN_ENABLED = function(stream) calculateDurability(stream) end,
		PLAYER_UNGHOST = function(stream)
			C_Timer.After(1, function() calculateDurability(stream) end)
		end,
		PLAYER_LOGIN = function(stream) calculateDurability(stream) end,
	},
}

EnhanceQoL.DataHub.RegisterStream(provider)

return provider
