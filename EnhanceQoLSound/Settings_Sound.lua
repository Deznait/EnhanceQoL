local parentAddonName = "EnhanceQoL"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

if not addon.Sounds or not addon.Sounds.soundFiles then return end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL_Sound")

local function GetLabel(key)
	return L[key] or key
end

local function IsPureNumbersTable(tbl)
	local hasEntries
	for _, v in pairs(tbl) do
		hasEntries = true
		if type(v) ~= "number" then return false end
	end
	return hasEntries and true or false
end

local function AllChildrenArePureNumbers(tbl)
	local hasEntries
	for _, child in pairs(tbl) do
		hasEntries = true
		if type(child) ~= "table" or not IsPureNumbersTable(child) then return false end
	end
	return hasEntries and true or false
end

local cSound = addon.functions.SettingsCreateCategory(nil, SOUND or SOUND_LABEL or "Sound", nil, "Sound")
addon.SettingsLayout.soundCategory = cSound

local function AddSoundOptions(path, data)
	if type(data) ~= "table" then return end

	if AllChildrenArePureNumbers(data) then
		local groupKey = table.concat(path, "_")
		local keys = {}
		for key in pairs(data) do table.insert(keys, key) end
		table.sort(keys, function(a, b)
			local la, lb = GetLabel(a), GetLabel(b)
			if la == lb then return tostring(a) < tostring(b) end
			return la < lb
		end)

		for _, key in ipairs(keys) do
			local varName = "sounds_" .. groupKey .. "_" .. key
			local label = GetLabel(key)
			if #path > 1 then label = GetLabel(path[#path]) .. " - " .. label end
			local soundList = data[key]

			addon.functions.SettingsCreateCheckbox(cSound, {
				var = varName,
				text = label,
				func = function(value)
					addon.db[varName] = value and true or false
					if type(soundList) == "table" then
						for _, soundID in ipairs(soundList) do
							if value then
								MuteSoundFile(soundID)
							else
								UnmuteSoundFile(soundID)
							end
						end
					end
				end,
				default = false,
			})
		end
	else
		local children = {}
		for key in pairs(data) do table.insert(children, key) end
		table.sort(children, function(a, b)
			local la, lb = GetLabel(a), GetLabel(b)
			if la == lb then return tostring(a) < tostring(b) end
			return la < lb
		end)

		for _, key in ipairs(children) do
			if type(data[key]) == "table" then
				table.insert(path, key)
				AddSoundOptions(path, data[key])
				table.remove(path)
			end
		end
	end
end

local topKeys = {}
for key in pairs(addon.Sounds.soundFiles) do table.insert(topKeys, key) end
table.sort(topKeys, function(a, b)
	local la, lb = GetLabel(a), GetLabel(b)
	if la == lb then return tostring(a) < tostring(b) end
	return la < lb
end)

for _, treeKey in ipairs(topKeys) do
	addon.functions.SettingsCreateHeadline(cSound, GetLabel(treeKey))
	AddSoundOptions({ treeKey }, addon.Sounds.soundFiles[treeKey])
end
