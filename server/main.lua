--[[
    Snowman Killfeed Status - Server
    Author: Snowman

    - Receives kill reports from victim clients (event driven, no loops).
    - Enriches with ESX data + real Discord profiles (cached).
    - Stores up to Config.MaxHistory kills in memory (optional SQL persistence).
    - Broadcasts live updates to admins who have the killfeed open.
    - Serves detailed live profiles on demand via ox_lib callbacks.
]]

local ESX = exports['es_extended']:getSharedObject()

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------
local killHistory  = {}   -- newest-first array of kill records
local killIdCounter = 0

local viewers = {}        -- [serverId] = true  (killfeed UI currently open)
local admins  = {}        -- [serverId] = true  (player is in an allowed group)

local statsByLicense = {} -- [license]  = { kills, deaths, headshots }

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------

local function dbg(...)
    if Config.Debug then print('[snowman_killfeed]', ...) end
end

local function getIdentifier(serverId, prefix)
    for _, id in ipairs(GetPlayerIdentifiers(serverId) or {}) do
        if id:sub(1, #prefix + 1) == prefix .. ':' then
            return id:sub(#prefix + 2)
        end
    end
    return nil
end

-- True when the player is in one of Config.AllowedGroups.
local function isAdmin(serverId)
    local xPlayer = ESX.GetPlayerFromId(serverId)
    if not xPlayer then return false end
    return Config.AllowedGroups[xPlayer.getGroup()] == true
end

local function weaponCategory(weaponHash, cause)
    if Config.WeaponCategories[weaponHash] then
        return Config.WeaponCategories[weaponHash]
    end
    if cause and Config.DeathTypeCategory[cause] then
        return Config.DeathTypeCategory[cause]
    end
    return 'unknown'
end

-- Per-license stats accumulator (session memory).
local function ensureStats(license)
    if not license then return nil end
    if not statsByLicense[license] then
        statsByLicense[license] = { kills = 0, deaths = 0, headshots = 0 }
    end
    return statsByLicense[license]
end

----------------------------------------------------------------------
-- PARTY BUILDERS
----------------------------------------------------------------------

-- Compact party object used inside kill cards (killer / victim summary).
-- Includes the real Discord avatar so cards never show fake avatars.
local function buildParty(serverId, snapshot)
    if not serverId then return nil end

    local online = GetPlayerName(serverId) ~= nil
    local name   = online and GetPlayerName(serverId) or 'Disconnected'
    local license = getIdentifier(serverId, 'license')
    local discordId = Discord.GetId(serverId)
    local profile = Discord.FetchProfile(discordId)

    local job, jobGrade
    local xPlayer = online and ESX.GetPlayerFromId(serverId) or nil
    if xPlayer then
        local jobData = xPlayer.getJob()
        job = jobData.label
        jobGrade = jobData.grade_label
    end

    return {
        serverId    = serverId,
        name        = name,
        license     = license,
        discordId   = discordId,
        discord     = profile,
        ping        = online and GetPlayerPing(serverId) or 0,
        job         = job or 'Unemployed',
        jobGrade    = jobGrade or '',
        online      = online,
        -- snapshot taken at the moment of the kill
        health      = snapshot and snapshot.health or 0,
        armor       = snapshot and snapshot.armor or 0,
        coords      = snapshot and snapshot.coords or { x = 0, y = 0, z = 0 },
        vehicle     = snapshot and snapshot.vehicle or 'On Foot',
        weapon      = snapshot and snapshot.weapon or 'Unarmed',
    }
end

----------------------------------------------------------------------
-- STORAGE
----------------------------------------------------------------------

local function storeRecord(record)
    table.insert(killHistory, 1, record)            -- newest first
    while #killHistory > Config.MaxHistory do        -- auto-delete oldest
        table.remove(killHistory)
    end
end

local function saveToDb(record)
    if not Config.Database.Enabled then return end
    MySQL.insert(([[
        INSERT INTO `%s`
            (kill_id, time, killer_name, killer_license, victim_name, victim_license,
             weapon, distance, headshot, suicide, vehicle_kill, explosion, cause, payload)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]]):format(Config.Database.Table), {
        record.id,
        record.time,
        record.killer and record.killer.name or 'Environment',
        record.killer and record.killer.license or '',
        record.victim and record.victim.name or 'Unknown',
        record.victim and record.victim.license or '',
        record.weaponLabel,
        record.distance,
        record.headshot and 1 or 0,
        record.suicide and 1 or 0,
        record.vehicleKill and 1 or 0,
        record.explosion and 1 or 0,
        record.cause,
        json.encode(record),
    })
end

----------------------------------------------------------------------
-- BROADCAST + NOTIFY
----------------------------------------------------------------------

local function broadcastKill(record)
    for viewer in pairs(viewers) do
        TriggerClientEvent('snowman_killfeed:client:newKill', viewer, record)
    end
end

-- Pushes a real on-screen killfeed entry. Lightweight payload (names, avatars,
-- weapon, flags) — no input focus is taken on the client.
local function pushKillfeed(record)
    if not Config.Killfeed.Enabled then return end

    local function partyBrief(party)
        if not party then return nil end
        return {
            name   = party.name,
            avatar = (party.discord and party.discord.avatarUrl) or nil,
            online = party.online,
        }
    end

    local entry = {
        killer      = (not record.suicide) and partyBrief(record.killer) or nil,
        victim      = partyBrief(record.victim),
        weaponLabel = record.weaponLabel,
        icon        = record.categoryIcon,
        distance    = record.distance,
        headshot    = record.headshot,
        suicide     = record.suicide,
        explosion   = record.explosion,
        vehicleKill = record.vehicleKill,
        -- client render hints (kept server-side so they stay in sync with config)
        position    = Config.Killfeed.Position,
        duration    = Config.Killfeed.Duration,
        maxShown    = Config.Killfeed.MaxShown,
        showAvatars = Config.Killfeed.ShowAvatars,
        showDistance= Config.Killfeed.ShowDistance,
    }

    if Config.Killfeed.Audience == 'everyone' then
        TriggerClientEvent('snowman_killfeed:client:killfeed', -1, entry)
    else
        for adminId in pairs(admins) do
            TriggerClientEvent('snowman_killfeed:client:killfeed', adminId, entry)
        end
    end
end

----------------------------------------------------------------------
-- KILL REPORTING (from victim client)
----------------------------------------------------------------------

RegisterNetEvent('snowman_killfeed:server:reportKill', function(payload)
    local victimId = source
    if type(payload) ~= 'table' then return end

    local killerId = payload.killerServerId
    -- Basic sanity: killer must currently be online to be treated as a player.
    if killerId and GetPlayerName(killerId) == nil then
        killerId = nil
    end

    local suicide = payload.suicide or (killerId ~= nil and killerId == victimId)

    -- Pull a fresh snapshot from the killer's client (online players only).
    local killerSnapshot
    if killerId and not suicide then
        killerSnapshot = lib.callback.await('snowman_killfeed:getSnapshot', killerId)
    end

    killIdCounter = killIdCounter + 1

    local weaponHash = payload.weaponHash or 0
    local category   = weaponCategory(weaponHash, payload.cause)

    -- For suicides / environment deaths the "killer" mirrors the victim or is nil.
    local killerParty
    if suicide then
        killerParty = buildParty(victimId, payload.victimSnapshot)
    elseif killerId then
        killerParty = buildParty(killerId, killerSnapshot)
    end
    local victimParty = buildParty(victimId, payload.victimSnapshot)

    -- Update session stats (keyed by license so they survive id reuse).
    do
        local vLicense = victimParty and victimParty.license
        local vStats = ensureStats(vLicense)
        if vStats then vStats.deaths = vStats.deaths + 1 end

        if not suicide and killerParty and killerParty.license then
            local kStats = ensureStats(killerParty.license)
            kStats.kills = kStats.kills + 1
            if payload.headshot then kStats.headshots = kStats.headshots + 1 end
        end
    end

    local record = {
        id           = killIdCounter,
        time         = os.time(),
        timeString   = os.date('%H:%M:%S'),
        weaponHash   = weaponHash,
        weaponLabel  = payload.weaponLabel or 'Unknown',
        category     = category,
        categoryIcon = Config.CategoryIcons[category] or Config.CategoryIcons.unknown,
        distance     = payload.distance or 0.0,
        headshot     = payload.headshot or false,
        suicide      = suicide or false,
        vehicleKill  = payload.vehicleKill or false,
        explosion    = payload.explosion or false,
        cause        = payload.cause or 'unknown',
        killer       = killerParty,
        victim       = victimParty,
    }

    storeRecord(record)
    broadcastKill(record)
    pushKillfeed(record)
    Webhook.LogKill(record)
    saveToDb(record)

    dbg(('Kill #%d: %s -> %s (%s)'):format(
        record.id,
        record.killer and record.killer.name or 'ENV',
        record.victim and record.victim.name or '??',
        record.weaponLabel))
end)

----------------------------------------------------------------------
-- DETAILED PROFILE (right panel, on kill selection)
----------------------------------------------------------------------

-- Builds the full Discord-style profile for a player, using live data when
-- they are online and falling back to the stored kill snapshot otherwise.
local function buildDetailedProfile(requesterId, serverId, fallbackParty)
    local online = serverId and GetPlayerName(serverId) ~= nil

    local snapshot
    if online then
        snapshot = lib.callback.await('snowman_killfeed:getSnapshot', serverId)
    end

    local base = buildParty(online and serverId or nil, snapshot) or fallbackParty or {}
    local license = base.license or (fallbackParty and fallbackParty.license)
    local stats = ensureStats(license) or { kills = 0, deaths = 0, headshots = 0 }

    -- ESX money / character (live only).
    local money, bank, characterName, firstName, lastName
    if online then
        local xPlayer = ESX.GetPlayerFromId(serverId)
        if xPlayer then
            money = xPlayer.getAccount('money') and xPlayer.getAccount('money').money or 0
            bank  = xPlayer.getAccount('bank') and xPlayer.getAccount('bank').money or 0
            firstName = xPlayer.get('firstName') or (xPlayer.getName and xPlayer.getName())
            lastName  = xPlayer.get('lastName')
            characterName = (firstName and lastName) and (firstName .. ' ' .. lastName) or base.name
        end
    end

    return {
        online        = online or false,
        status        = online and ((snapshot and snapshot.health and snapshot.health > 0) and 'Alive' or 'Dead') or 'Offline',
        name          = base.name,
        characterName = characterName or base.name,
        discord       = base.discord,
        discordId     = base.discordId,
        license       = license or 'Unknown',
        ping          = base.ping or 0,
        job           = base.job,
        jobGrade      = base.jobGrade,
        money         = money or 0,
        bank          = bank or 0,
        health        = snapshot and snapshot.health or base.health or 0,
        armor         = snapshot and snapshot.armor or base.armor or 0,
        vehicle       = snapshot and snapshot.vehicle or base.vehicle,
        weapon        = snapshot and snapshot.weapon or base.weapon,

        -- Stats box
        stats = {
            kills     = stats.kills,
            deaths    = stats.deaths,
            headshots = stats.headshots,
        },
    }
end

lib.callback.register('snowman_killfeed:fetchProfile', function(requesterId, serverId, fallbackParty)
    if not isAdmin(requesterId) then return nil end
    return buildDetailedProfile(requesterId, serverId, fallbackParty)
end)

----------------------------------------------------------------------
-- COMMAND + UI OPEN/CLOSE
----------------------------------------------------------------------

RegisterCommand(Config.Command, function(source)
    if source == 0 then
        print('[snowman_killfeed] This command must be run in-game.')
        return
    end
    if not isAdmin(source) then
        TriggerClientEvent('snowman_killfeed:client:denied', source)
        return
    end

    viewers[source] = true
    Webhook.LogPanelOpen(source)
    TriggerClientEvent('snowman_killfeed:client:open', source, {
        history = killHistory,
        config  = {
            theme         = Config.Theme,
            categoryIcons = Config.CategoryIcons,
            maxHistory    = Config.MaxHistory,
            adminActions  = Config.AdminActions.Events,
        },
    })
end, false)

RegisterNetEvent('snowman_killfeed:server:closed', function()
    viewers[source] = nil
end)

-- Diagnostic: prints YOUR discord id + bot-token state + fetch result to the
-- SERVER console. Helps pinpoint why a profile shows as "Unknown User".
RegisterCommand('killfeed_discordtest', function(source)
    if source == 0 then
        print('[snowman_killfeed] Run this in-game.')
        return
    end
    if not isAdmin(source) then return end

    local id  = Discord.GetId(source)
    local tok = Config.Discord.BotToken
    local tokState = (not tok or tok == '' or tok == 'YOUR_DISCORD_BOT_TOKEN_HERE')
        and 'NOT SET' or ('set (' .. #tok .. ' chars)')

    print(('[snowman_killfeed] --- Discord test for %s (id %s) ---'):format(GetPlayerName(source), source))
    print(('[snowman_killfeed] discord identifier: %s'):format(
        id and ('discord:' .. id) or 'NONE  (player has no Discord identifier — is the Discord app running?)'))
    print(('[snowman_killfeed] bot token: %s | Discord.Enabled: %s'):format(tokState, tostring(Config.Discord.Enabled)))

    if id then
        CreateThread(function()
            local profile = Discord.FetchProfile(id)
            print(('[snowman_killfeed] fetch result: username=%s, isReal=%s'):format(
                tostring(profile.username), tostring(profile.isReal)))
            if not profile.isReal then
                print('[snowman_killfeed] -> fallback returned. Set Config.Debug = true for the HTTP reason above.')
            end
        end)
    end
end, false)

----------------------------------------------------------------------
-- ADMIN ACTIONS (built-in lightweight handlers + configurable events)
----------------------------------------------------------------------

-- Generic dispatcher coming from NUI. action = key in Config.AdminActions.Events
RegisterNetEvent('snowman_killfeed:server:adminAction', function(action, targetId)
    local src = source
    if not isAdmin(src) then return end
    if not targetId or GetPlayerName(targetId) == nil then
        TriggerClientEvent('snowman_killfeed:client:notify', src, {
            title = 'Action failed', desc = 'Target is offline.', type = 'error',
        })
        return
    end

    Webhook.LogAdminAction(src, action, targetId)

    -- ox_lib feedback to the admin for every action.
    local ACTION_LABELS = {
        teleportToKiller = 'Teleported to the killer.',
        teleportToVictim = 'Teleported to the victim.',
        bringKiller      = 'Brought the killer to you.',
        bringVictim      = 'Brought the victim to you.',
        heal             = 'Target healed.',
        revive           = 'Target revived.',
    }
    TriggerClientEvent('snowman_killfeed:client:notify', src, {
        title = 'Killfeed',
        desc  = ACTION_LABELS[action] or 'Action completed.',
        type  = 'success',
    })

    local eventName = Config.AdminActions.Events[action]
    if eventName then
        -- Fire the configurable server event so external frameworks can hook in.
        TriggerEvent(eventName, src, targetId, action)
    end

    if not Config.AdminActions.UseBuiltIn then return end

    -- Built-in conveniences (safe no-ops if you delegate everything).
    if action == 'teleportToKiller' or action == 'teleportToVictim' then
        local coords = GetEntityCoords(GetPlayerPed(targetId))
        TriggerClientEvent('snowman_killfeed:client:teleport', src, {
            x = coords.x, y = coords.y, z = coords.z,
        })
    elseif action == 'bringKiller' or action == 'bringVictim' then
        local coords = GetEntityCoords(GetPlayerPed(src))
        TriggerClientEvent('snowman_killfeed:client:teleportTarget', targetId, {
            x = coords.x, y = coords.y, z = coords.z,
        })
    elseif action == 'heal' then
        TriggerClientEvent('snowman_killfeed:client:heal', targetId)
    elseif action == 'revive' then
        -- Try common revive events; harmless if absent.
        TriggerClientEvent('esx_ambulancejob:revive', targetId)
        TriggerEvent('hospital:server:revive', targetId)
    end
end)

----------------------------------------------------------------------
-- PLAYER LIFECYCLE
----------------------------------------------------------------------

AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    if Config.AllowedGroups[xPlayer.getGroup()] then
        admins[playerId] = true
    end
end)

AddEventHandler('esx:setGroup', function(playerId, lastGroup, newGroup)
    admins[playerId] = Config.AllowedGroups[newGroup] == true or nil
end)

AddEventHandler('playerDropped', function()
    local src = source
    viewers[src] = nil
    admins[src]  = nil
end)

-- Re-seed the admin set for players already online (e.g. after a resource
-- restart, when esx:playerLoaded will not fire again).
AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(1000)
        local players = ESX.GetExtendedPlayers and ESX.GetExtendedPlayers() or {}
        for _, xPlayer in pairs(players) do
            local sid = xPlayer.source
            if Config.AllowedGroups[xPlayer.getGroup()] then
                admins[sid] = true
            end
        end
        dbg(('Seeded %d online players'):format(#players))
    end)
end)

----------------------------------------------------------------------
-- OPTIONAL DB BOOTSTRAP
----------------------------------------------------------------------

CreateThread(function()
    if not Config.Database.Enabled then return end

    MySQL.query(([[
        CREATE TABLE IF NOT EXISTS `%s` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `kill_id` INT,
            `time` INT,
            `killer_name` VARCHAR(64),
            `killer_license` VARCHAR(64),
            `victim_name` VARCHAR(64),
            `victim_license` VARCHAR(64),
            `weapon` VARCHAR(64),
            `distance` FLOAT,
            `headshot` TINYINT(1),
            `suicide` TINYINT(1),
            `vehicle_kill` TINYINT(1),
            `explosion` TINYINT(1),
            `cause` VARCHAR(32),
            `payload` LONGTEXT,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ]]):format(Config.Database.Table))

    -- Load the most recent kills back into memory on boot.
    local rows = MySQL.query.await(('SELECT payload FROM `%s` ORDER BY id DESC LIMIT ?')
        :format(Config.Database.Table), { Config.MaxHistory })
    if rows then
        for i = #rows, 1, -1 do
            local ok, record = pcall(json.decode, rows[i].payload)
            if ok and record then
                killIdCounter = math.max(killIdCounter, record.id or 0)
                table.insert(killHistory, 1, record)
            end
        end
        dbg(('Loaded %d kills from database'):format(#rows))
    end
end)
