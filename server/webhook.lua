--[[
    Snowman Killfeed Status - Discord Webhook Logs
    Author: Snowman

    Sends clean embed logs to a Discord channel via webhook. Fire-and-forget,
    non-blocking. The webhook URL is a server-only secret (server/sv_config.lua).
]]

Webhook = {}

local function cfg() return Config.Webhook or {} end

-- True only when logging is enabled and a real URL is configured.
local function ready()
    local c = cfg()
    local url = c.Url
    return c.Enabled
        and url and url ~= '' and url ~= 'YOUR_WEBHOOK_URL_HERE'
end

-- POST a single embed. Discord returns 204 on success.
local function send(embed)
    if not ready() then return end
    local c = cfg()

    local payload = {
        username   = c.Username ~= '' and c.Username or 'Killfeed Logs',
        avatar_url = (c.Avatar and c.Avatar ~= '') and c.Avatar or nil,
        embeds     = { embed },
    }

    PerformHttpRequest(c.Url, function(status)
        if Config.Debug and status ~= 200 and status ~= 204 then
            print(('[snowman_killfeed] Webhook HTTP %s'):format(tostring(status)))
        end
    end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end

-- Builds the "identifiers" line for a party (Discord mention, license, id).
local function identifierField(party, label)
    if not cfg().IncludeIdentifiers or not party then return nil end
    local parts = {}
    if party.discordId then parts[#parts + 1] = ('<@%s>'):format(party.discordId) end
    if party.license   then parts[#parts + 1] = ('`%s`'):format(party.license) end
    if party.serverId  then parts[#parts + 1] = ('ID %s'):format(party.serverId) end
    if #parts == 0 then return nil end
    return { name = label, value = table.concat(parts, ' • '), inline = false }
end

----------------------------------------------------------------------
-- PUBLIC LOGGERS
----------------------------------------------------------------------

-- Logs a kill record.
function Webhook.LogKill(record)
    local c = cfg()
    if not c.LogKills then return end
    if c.KillsPlayerOnly and (record.suicide or not record.killer) then return end

    local killerName = record.killer and record.killer.name or 'Environment'
    local victimName = record.victim and record.victim.name or 'Unknown'

    local fields = {
        { name = 'Killer',   value = killerName, inline = true },
        { name = 'Victim',   value = victimName, inline = true },
        { name = 'Weapon',   value = record.weaponLabel or 'Unknown', inline = true },
        { name = 'Distance', value = (record.distance or 0) .. 'm', inline = true },
        { name = 'Headshot', value = record.headshot and 'Yes' or 'No', inline = true },
        { name = 'Type',     value = record.suicide and 'Suicide' or (record.cause or 'kill'), inline = true },
    }

    local kIds = identifierField(record.killer, 'Killer')
    local vIds = identifierField(record.victim, 'Victim')
    if kIds then fields[#fields + 1] = kIds end
    if vIds then fields[#fields + 1] = vIds end

    local embed = {
        title  = 'Kill Logged',
        color  = (c.Colors and c.Colors.kill) or 0xE0626F,
        fields = fields,
        footer = { text = ('Kill #%s • %s'):format(record.id or '?', record.timeString or '') },
    }

    local kav = record.killer and record.killer.discord and record.killer.discord.avatarUrl
    if kav then embed.author = { name = killerName, icon_url = kav } end
    local vav = record.victim and record.victim.discord and record.victim.discord.avatarUrl
    if vav then embed.thumbnail = { url = vav } end

    send(embed)
end

-- Logs an admin action (teleport / bring / heal / revive).
function Webhook.LogAdminAction(adminId, action, targetId)
    local c = cfg()
    if not c.LogAdminActions then return end

    local adminName  = GetPlayerName(adminId) or '?'
    local targetName = (targetId and GetPlayerName(targetId)) or '?'

    send({
        title  = 'Admin Action',
        color  = (c.Colors and c.Colors.admin) or 0x6E9BEF,
        fields = {
            { name = 'Admin',  value = ('%s (ID %s)'):format(adminName, adminId), inline = true },
            { name = 'Action', value = tostring(action), inline = true },
            { name = 'Target', value = ('%s (ID %s)'):format(targetName, tostring(targetId)), inline = true },
        },
        footer = { text = os.date('%Y-%m-%d %H:%M:%S') },
    })
end

-- Logs an admin opening the killfeed panel.
function Webhook.LogPanelOpen(adminId)
    local c = cfg()
    if not c.LogPanelOpen then return end

    local name = GetPlayerName(adminId) or '?'
    send({
        title       = 'Killfeed Opened',
        color       = (c.Colors and c.Colors.info) or 0x58BD92,
        description = ('**%s** (ID %s) opened the killfeed panel.'):format(name, adminId),
        footer      = { text = os.date('%Y-%m-%d %H:%M:%S') },
    })
end
