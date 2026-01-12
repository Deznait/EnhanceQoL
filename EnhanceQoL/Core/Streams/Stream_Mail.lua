-- luacheck: globals EnhanceQoL HasNewMail GetLatestThreeSenders HAVE_MAIL HAVE_MAIL_FROM C_GameRules Enum MAIL_LABEL MAIL INBOX
local addonName, addon = ...

local MAIL_ICON_ATLAS = "ui-hud-minimap-mail-up"
local DEFAULT_FONT_SIZE = 14

local function getMailTitle()
	if MAIL_LABEL then return MAIL_LABEL end
	if MAIL then return MAIL end
	if INBOX then return INBOX end
	return "Mail"
end

local function isNotificationDisabled()
	if C_GameRules and C_GameRules.IsGameRuleActive and Enum and Enum.GameRule then return C_GameRules.IsGameRuleActive(Enum.GameRule.IngameMailNotificationDisabled) end
	return false
end

local function getMailSenders()
	if not GetLatestThreeSenders then return {} end
	local sender1, sender2, sender3 = GetLatestThreeSenders()
	local senders = {}
	if sender1 and sender1 ~= "" then senders[#senders + 1] = sender1 end
	if sender2 and sender2 ~= "" then senders[#senders + 1] = sender2 end
	if sender3 and sender3 ~= "" then senders[#senders + 1] = sender3 end
	return senders
end

local function buildTooltip()
	local senders = getMailSenders()
	local header = (#senders >= 1 and HAVE_MAIL_FROM) or HAVE_MAIL or "You have mail."
	if #senders == 0 then return header end
	local lines = { header }
	for _, sender in ipairs(senders) do
		lines[#lines + 1] = sender
	end
	return table.concat(lines, "\n")
end

local function updateMail(stream)
	local hasMail = HasNewMail and HasNewMail()
	if not hasMail or isNotificationDisabled() then
		stream.snapshot.hidden = true
		stream.snapshot.text = nil
		stream.snapshot.tooltip = nil
		return
	end

	stream.snapshot.hidden = nil
	stream.snapshot.fontSize = DEFAULT_FONT_SIZE
	stream.snapshot.text = ("|A:%s:%d:%d|a"):format(MAIL_ICON_ATLAS, DEFAULT_FONT_SIZE, DEFAULT_FONT_SIZE)
	stream.snapshot.tooltip = buildTooltip()
end

local provider = {
	id = "mail",
	version = 1,
	title = getMailTitle(),
	poll = 300,
	update = updateMail,
	events = {
		UPDATE_PENDING_MAIL = function(s) addon.DataHub:RequestUpdate(s) end,
		PLAYER_ENTERING_WORLD = function(s) addon.DataHub:RequestUpdate(s) end,
	},
}

EnhanceQoL.DataHub.RegisterStream(provider)

return provider
