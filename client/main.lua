--[[
    Snowman Killfeed Status - Client
    Author: Snowman

    - Detects the LOCAL player's death (event driven) and reports it to the
      server with accurate killer / weapon / headshot / distance data.
    - Provides a live snapshot callback used by the server for both killer data
      and detailed profile lookups.
    - Manages the NUI (open / close / live updates) and admin action plumbing.

    Idle cost: 0.00ms. There is no per-frame loop; a short watcher thread runs
    only while the player is dead and stops as soon as they respawn.
]]

local ESX = exports['es_extended']:getSharedObject()

local uiOpen        = false
local deathReported = false   -- debounce: one report per death

----------------------------------------------------------------------
-- SNAPSHOT
----------------------------------------------------------------------

-- Returns the current state of the LOCAL player. Used as victim data on death
-- and requested by the server for killer / profile data.
local function getLocalSnapshot()
    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local veh    = GetVehiclePedIsIn(ped, false)

    local vehicleName = 'On Foot'
    if veh and veh ~= 0 then
        local model = GetEntityModel(veh)
        local label = GetLabelText(GetDisplayNameFromVehicleModel(model))
        if not label or label == 'NULL' then
            label = GetDisplayNameFromVehicleModel(model)
        end
        vehicleName = label or 'Vehicle'
    end

    -- GTA health is 100..200; normalise to 0..100 for display.
    local rawHealth = GetEntityHealth(ped)
    local health = rawHealth > 100 and (rawHealth - 100) or 0

    return {
        health  = health,
        armor   = GetPedArmour(ped),
        coords  = {
            x = math.floor(coords.x * 100) / 100,
            y = math.floor(coords.y * 100) / 100,
            z = math.floor(coords.z * 100) / 100,
        },
        weapon  = Utils.GetWeaponLabel(Utils.GetCurrentWeapon(ped)),
        vehicle = vehicleName,
    }
end

-- Server may ask any client for its current snapshot.
lib.callback.register('snowman_killfeed:getSnapshot', function()
    return getLocalSnapshot()
end)

----------------------------------------------------------------------
-- DEATH DETECTION
----------------------------------------------------------------------

-- Builds and sends the kill report. Uses the reliable death natives
-- (GetPedSourceOfDeath / GetPedCauseOfDeath) for accuracy.
local function processLocalDeath()
    local ped = PlayerPedId()

    local killerEntity = GetPedSourceOfDeath(ped)
    local weaponHash   = GetPedCauseOfDeath(ped)
    local victimCoords = GetEntityCoords(ped)

    local killerServerId = Utils.GetPlayerServerId(killerEntity)
    local myServerId     = GetPlayerServerId(PlayerId())
    local suicide        = (killerServerId == myServerId)
        or (killerEntity == ped)
        or (killerEntity == 0)

    local cause = Utils.ClassifyCause(ped, killerEntity, weaponHash)

    local distance = 0.0
    if killerEntity and killerEntity ~= 0 and DoesEntityExist(killerEntity) and not suicide then
        distance = Utils.Distance(victimCoords, GetEntityCoords(killerEntity))
    end

    TriggerServerEvent('snowman_killfeed:server:reportKill', {
        killerServerId = (not suicide) and killerServerId or nil,
        weaponHash     = weaponHash,
        weaponLabel    = Utils.GetWeaponLabel(weaponHash),
        distance       = distance,
        headshot       = Utils.WasHeadshot(ped),
        suicide        = suicide,
        vehicleKill    = (cause == 'vehicle'),
        explosion      = (cause == 'explosion'),
        cause          = cause,
        victimSnapshot = getLocalSnapshot(),
    })
end

-- Lightweight watcher: only spins while dead, then resets the debounce and
-- exits. Keeps idle usage at 0.00ms.
local function watchRespawn()
    CreateThread(function()
        while deathReported do
            Wait(1000)
            if not IsEntityDead(PlayerPedId()) then
                deathReported = false
            end
        end
    end)
end

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end

    local victim = args[1]
    -- Only the victim's own client reports — guarantees accurate local data and
    -- avoids duplicate reports from every nearby player.
    if victim ~= PlayerPedId() then return end
    if deathReported then return end
    if not IsEntityDead(victim) then return end

    deathReported = true
    -- Give the engine a frame so cause/source-of-death are populated.
    SetTimeout(50, function()
        processLocalDeath()
        watchRespawn()
    end)
end)

-- Safety net: clear the debounce on respawn events too.
AddEventHandler('esx:onPlayerSpawn', function() deathReported = false end)
AddEventHandler('playerSpawned',     function() deathReported = false end)

----------------------------------------------------------------------
-- NUI: OPEN / CLOSE / LIVE UPDATES
----------------------------------------------------------------------

RegisterNetEvent('snowman_killfeed:client:open', function(data)
    if uiOpen then return end
    uiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action  = 'open',
        history = data.history,
        config  = data.config,
    })
end)

RegisterNetEvent('snowman_killfeed:client:newKill', function(record)
    if not uiOpen then return end
    SendNUIMessage({ action = 'newKill', kill = record })
end)

-- Real on-screen killfeed entry. Does NOT take input focus, so it renders as a
-- pure HUD overlay over normal gameplay.
RegisterNetEvent('snowman_killfeed:client:killfeed', function(entry)
    SendNUIMessage({ action = 'killfeedAdd', entry = entry })
end)

-- Safe notification helper. Uses ox_lib when available, and falls back to a
-- native game notification so admins still get feedback even if ox_lib failed
-- to load for any reason.
local function notify(opts)
    if Config.Notifications and Config.Notifications.Enabled == false then return end

    if lib and lib.notify then
        lib.notify(opts)
        return
    end

    -- Native fallback (top-left feed).
    BeginTextCommandThefeedPost('STRING')
    local msg = (opts.title and (opts.title .. ': ') or '') .. (opts.description or '')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, true)
end

local NOTIFY_ICONS = {
    success = 'circle-check',
    error   = 'circle-xmark',
    warning = 'triangle-exclamation',
    inform  = 'circle-info',
}

RegisterNetEvent('snowman_killfeed:client:denied', function()
    notify({
        title       = 'Killfeed',
        description = 'You do not have permission to use this.',
        type        = 'error',
        position    = Config.Notifications.Position,
        duration    = Config.Notifications.Duration,
        icon        = NOTIFY_ICONS.error,
    })
end)

RegisterNetEvent('snowman_killfeed:client:notify', function(data)
    local nType = data.type or 'inform'
    notify({
        title       = data.title or 'Killfeed',
        description = data.desc,
        type        = nType,
        position    = Config.Notifications.Position,
        duration    = Config.Notifications.Duration,
        icon        = NOTIFY_ICONS[nType] or NOTIFY_ICONS.inform,
    })
end)

local function closeUi()
    if not uiOpen then return end
    uiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    TriggerServerEvent('snowman_killfeed:server:closed')
end

----------------------------------------------------------------------
-- NUI CALLBACKS
----------------------------------------------------------------------

RegisterNUICallback('close', function(_, cb)
    closeUi()
    cb({ ok = true })
end)

-- Fetch a detailed live profile for the selected kill's player.
RegisterNUICallback('fetchProfile', function(payload, cb)
    local profile = lib.callback.await(
        'snowman_killfeed:fetchProfile', false,
        payload.serverId, payload.fallback
    )
    cb(profile or {})
end)

-- Admin action buttons.
RegisterNUICallback('adminAction', function(payload, cb)
    if payload.action and payload.targetId then
        TriggerServerEvent('snowman_killfeed:server:adminAction', payload.action, payload.targetId)
    end
    cb({ ok = true })
end)

-- Clipboard copy is handled in JS; this is here for parity / future use.
RegisterNUICallback('copy', function(_, cb)
    cb({ ok = true })
end)

----------------------------------------------------------------------
-- ADMIN ACTION RESULTS (teleport, bring)
----------------------------------------------------------------------

RegisterNetEvent('snowman_killfeed:client:teleport', function(coords)
    local ped = PlayerPedId()
    SetEntityCoords(ped, coords.x, coords.y, coords.z + 1.0, false, false, false, false)
end)

RegisterNetEvent('snowman_killfeed:client:teleportTarget', function(coords)
    local ped = PlayerPedId()
    SetEntityCoords(ped, coords.x, coords.y, coords.z + 1.0, false, false, false, false)
end)

RegisterNetEvent('snowman_killfeed:client:heal', function()
    local ped = PlayerPedId()
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    SetPedArmour(ped, 100)
    ClearPedBloodDamage(ped)
end)

----------------------------------------------------------------------
-- CLEANUP
----------------------------------------------------------------------

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and uiOpen then
        SetNuiFocus(false, false)
    end
end)
