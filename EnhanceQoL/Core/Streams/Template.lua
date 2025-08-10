-- luacheck: globals EnhanceQoL
--[[
Template stream provider for EnhanceQoL's DataHub.
Copy this file and adjust the fields to create your own stream.
]]

local provider = {
	id = "example", -- required: unique identifier for the stream
	version = 1, -- required: increment when the provider changes
	title = "Example Stream", -- required: human readable title
	columns = { -- required: column definitions for the output
		{ key = "name", title = "Name" }, -- column showing a name
		{ key = "value", title = "Value" }, -- column showing a value
	},
	poll = 30, -- required: seconds between collect calls
	collect = function(ctx) -- required: gather data and populate ctx.rows
		local rows = ctx.rows
		local row = ctx.acquireRow()
		row.name = "Example"
		row.value = 42
		rows[#rows + 1] = row
	end,
	filter = function(row) -- optional: return false to drop a row
		return true
	end,
	actions = { -- optional: custom callbacks exposed to consumers
		export = function(snapshot)
			-- handle custom action (e.g., export the snapshot)
		end,
	},
	settings = { -- optional: default configuration for this stream
		enabled = true,
	},
}

-- Register the stream with the DataHub
EnhanceQoL.DataHub.RegisterStream(provider)

return provider
