--[[
    Snowman Killfeed Status - Client Utilities
    Author: Snowman

    Pure helper functions used by the kill detector. Kept separate so the main
    file stays focused on event flow.
]]

Utils = {}

-- Human readable weapon label from a weapon hash. Backed by a hash->label
-- lookup (WeaponLabelCache) built once on load. O(1), never loops.
function Utils.GetWeaponLabel(weaponHash)
    if not weaponHash or weaponHash == 0 then return 'Unknown' end
    return WeaponLabelCache[weaponHash] or 'Weapon'
end

-- Distance between two vectors, rounded to 1 decimal.
function Utils.Distance(a, b)
    if not a or not b then return 0.0 end
    return math.floor(#(a - b) * 10.0 + 0.5) / 10.0
end

-- Returns true when the fatal shot hit a head bone.
function Utils.WasHeadshot(victimPed)
    -- 0x796E -> SKEL_Head bone id 31086. GetPedLastDamageBone gives the last
    -- bone that took damage, which on a kill is the killing hit.
    local hit, bone = GetPedLastDamageBone(victimPed)
    if hit == 1 and (bone == 31086 or bone == 39317) then
        return true
    end
    return false
end

-- Classify a death using GTA death cause info when there is no clear weapon.
-- Returns one of: pvp, vehicle, explosion, fire, drown, fall, suicide, animal, unknown
function Utils.ClassifyCause(victimPed, killerEntity, weaponHash)
    -- Drowning
    if IsPedSwimmingUnderWater(victimPed) or IsEntityInWater(victimPed) then
        if weaponHash == `WEAPON_DROWNING` or weaponHash == `WEAPON_DROWNING_IN_VEHICLE` then
            return 'drown'
        end
    end

    if weaponHash == `WEAPON_DROWNING` or weaponHash == `WEAPON_DROWNING_IN_VEHICLE` then
        return 'drown'
    end

    if weaponHash == `WEAPON_FALL` then
        return 'fall'
    end

    if weaponHash == `WEAPON_FIRE` or weaponHash == `WEAPON_MOLOTOV` or weaponHash == `WEAPON_PETROLCAN` then
        return 'fire'
    end

    if weaponHash == `WEAPON_EXPLOSION` or weaponHash == `WEAPON_STICKYBOMB`
        or weaponHash == `WEAPON_GRENADE` or weaponHash == `WEAPON_RPG` then
        return 'explosion'
    end

    -- Vehicle (ran over / vehicle weapon)
    if killerEntity and killerEntity ~= 0 and DoesEntityExist(killerEntity) then
        if IsEntityAVehicle(killerEntity) then
            return 'vehicle'
        end
        if weaponHash == `WEAPON_RAMMED_BY_CAR` or weaponHash == `WEAPON_RUN_OVER_BY_CAR` then
            return 'vehicle'
        end
        -- Animal killer
        if IsEntityAPed(killerEntity) and not IsPedAPlayer(killerEntity) then
            local model = GetEntityModel(killerEntity)
            if IsThisModelABird and IsThisModelABird(model) then return 'animal' end
        end
    end

    return 'unknown'
end

-- Resolve the network/server id for an entity if it is a player ped.
function Utils.GetPlayerServerId(ped)
    if not ped or ped == 0 then return nil end
    if not IsPedAPlayer(ped) then return nil end
    local player = NetworkGetPlayerIndexFromPed(ped)
    if player == -1 then return nil end
    return GetPlayerServerId(player)
end

-- Current weapon hash for a ped (0 when unarmed/unknown).
function Utils.GetCurrentWeapon(ped)
    local _, hash = GetCurrentPedWeapon(ped, true)
    return hash or 0
end

-- Reverse map of weapon hash -> readable label. Hashes are computed at compile
-- time via backticks, so this is a direct, allocation-free lookup at runtime.
-- Special pseudo-weapons (fall, fire, drown...) are included so environment
-- deaths read nicely in the feed.
WeaponLabelCache = {
    [`WEAPON_UNARMED`]          = 'Fists',
    [`WEAPON_PISTOL`]           = 'Pistol',
    [`WEAPON_PISTOL_MK2`]       = 'Pistol Mk II',
    [`WEAPON_COMBATPISTOL`]     = 'Combat Pistol',
    [`WEAPON_APPISTOL`]         = 'AP Pistol',
    [`WEAPON_PISTOL50`]         = 'Pistol .50',
    [`WEAPON_SNSPISTOL`]        = 'SNS Pistol',
    [`WEAPON_SNSPISTOL_MK2`]    = 'SNS Pistol Mk II',
    [`WEAPON_HEAVYPISTOL`]      = 'Heavy Pistol',
    [`WEAPON_VINTAGEPISTOL`]    = 'Vintage Pistol',
    [`WEAPON_MARKSMANPISTOL`]   = 'Marksman Pistol',
    [`WEAPON_REVOLVER`]         = 'Heavy Revolver',
    [`WEAPON_REVOLVER_MK2`]     = 'Heavy Revolver Mk II',
    [`WEAPON_DOUBLEACTION`]     = 'Double Action Revolver',
    [`WEAPON_CERAMICPISTOL`]    = 'Ceramic Pistol',
    [`WEAPON_NAVYREVOLVER`]     = 'Navy Revolver',
    [`WEAPON_STUNGUN`]          = 'Stun Gun',
    [`WEAPON_FLAREGUN`]         = 'Flare Gun',
    [`WEAPON_MICROSMG`]         = 'Micro SMG',
    [`WEAPON_SMG`]              = 'SMG',
    [`WEAPON_SMG_MK2`]          = 'SMG Mk II',
    [`WEAPON_ASSAULTSMG`]       = 'Assault SMG',
    [`WEAPON_COMBATPDW`]        = 'Combat PDW',
    [`WEAPON_MACHINEPISTOL`]    = 'Machine Pistol',
    [`WEAPON_MINISMG`]          = 'Mini SMG',
    [`WEAPON_PUMPSHOTGUN`]      = 'Pump Shotgun',
    [`WEAPON_PUMPSHOTGUN_MK2`]  = 'Pump Shotgun Mk II',
    [`WEAPON_SAWNOFFSHOTGUN`]   = 'Sawed-Off Shotgun',
    [`WEAPON_BULLPUPSHOTGUN`]   = 'Bullpup Shotgun',
    [`WEAPON_ASSAULTSHOTGUN`]   = 'Assault Shotgun',
    [`WEAPON_HEAVYSHOTGUN`]     = 'Heavy Shotgun',
    [`WEAPON_DBSHOTGUN`]        = 'Double Barrel Shotgun',
    [`WEAPON_AUTOSHOTGUN`]      = 'Sweeper Shotgun',
    [`WEAPON_COMBATSHOTGUN`]    = 'Combat Shotgun',
    [`WEAPON_ASSAULTRIFLE`]     = 'Assault Rifle',
    [`WEAPON_ASSAULTRIFLE_MK2`] = 'Assault Rifle Mk II',
    [`WEAPON_CARBINERIFLE`]     = 'Carbine Rifle',
    [`WEAPON_CARBINERIFLE_MK2`] = 'Carbine Rifle Mk II',
    [`WEAPON_ADVANCEDRIFLE`]    = 'Advanced Rifle',
    [`WEAPON_SPECIALCARBINE`]   = 'Special Carbine',
    [`WEAPON_SPECIALCARBINE_MK2`] = 'Special Carbine Mk II',
    [`WEAPON_BULLPUPRIFLE`]     = 'Bullpup Rifle',
    [`WEAPON_BULLPUPRIFLE_MK2`] = 'Bullpup Rifle Mk II',
    [`WEAPON_COMPACTRIFLE`]     = 'Compact Rifle',
    [`WEAPON_MILITARYRIFLE`]    = 'Military Rifle',
    [`WEAPON_HEAVYRIFLE`]       = 'Heavy Rifle',
    [`WEAPON_TACTICALRIFLE`]    = 'Service Carbine',
    [`WEAPON_MG`]               = 'Machine Gun',
    [`WEAPON_COMBATMG`]         = 'Combat MG',
    [`WEAPON_COMBATMG_MK2`]     = 'Combat MG Mk II',
    [`WEAPON_GUSENBERG`]        = 'Gusenberg Sweeper',
    [`WEAPON_SNIPERRIFLE`]      = 'Sniper Rifle',
    [`WEAPON_HEAVYSNIPER`]      = 'Heavy Sniper',
    [`WEAPON_HEAVYSNIPER_MK2`]  = 'Heavy Sniper Mk II',
    [`WEAPON_MARKSMANRIFLE`]    = 'Marksman Rifle',
    [`WEAPON_MARKSMANRIFLE_MK2`] = 'Marksman Rifle Mk II',
    [`WEAPON_PRECISIONRIFLE`]   = 'Precision Rifle',
    [`WEAPON_KNIFE`]            = 'Knife',
    [`WEAPON_DAGGER`]           = 'Antique Cavalry Dagger',
    [`WEAPON_SWITCHBLADE`]      = 'Switchblade',
    [`WEAPON_MACHETE`]          = 'Machete',
    [`WEAPON_HATCHET`]          = 'Hatchet',
    [`WEAPON_STONE_HATCHET`]    = 'Stone Hatchet',
    [`WEAPON_BOTTLE`]           = 'Broken Bottle',
    [`WEAPON_KNUCKLE`]          = 'Knuckle Duster',
    [`WEAPON_BAT`]              = 'Baseball Bat',
    [`WEAPON_CROWBAR`]          = 'Crowbar',
    [`WEAPON_GOLFCLUB`]         = 'Golf Club',
    [`WEAPON_HAMMER`]           = 'Hammer',
    [`WEAPON_NIGHTSTICK`]       = 'Nightstick',
    [`WEAPON_WRENCH`]           = 'Pipe Wrench',
    [`WEAPON_BATTLEAXE`]        = 'Battle Axe',
    [`WEAPON_POOLCUE`]          = 'Pool Cue',
    [`WEAPON_FLASHLIGHT`]       = 'Flashlight',
    [`WEAPON_GRENADE`]          = 'Grenade',
    [`WEAPON_STICKYBOMB`]       = 'Sticky Bomb',
    [`WEAPON_PROXMINE`]         = 'Proximity Mine',
    [`WEAPON_PIPEBOMB`]         = 'Pipe Bomb',
    [`WEAPON_RPG`]              = 'RPG',
    [`WEAPON_GRENADELAUNCHER`]  = 'Grenade Launcher',
    [`WEAPON_HOMINGLAUNCHER`]   = 'Homing Launcher',
    [`WEAPON_COMPACTLAUNCHER`]  = 'Compact Grenade Launcher',
    [`WEAPON_RAILGUN`]          = 'Railgun',
    [`WEAPON_MOLOTOV`]          = 'Molotov',
    [`WEAPON_PETROLCAN`]        = 'Jerry Can',
    [`WEAPON_FIREWORK`]         = 'Firework Launcher',
    [`WEAPON_FLARE`]            = 'Flare',
    [`WEAPON_HAZARDCAN`]        = 'Hazardous Jerry Can',
    -- Pseudo / environmental causes
    [`WEAPON_FALL`]                 = 'Fall Damage',
    [`WEAPON_DROWNING`]             = 'Drowning',
    [`WEAPON_DROWNING_IN_VEHICLE`]  = 'Drowning (Vehicle)',
    [`WEAPON_FIRE`]                 = 'Fire',
    [`WEAPON_EXPLOSION`]            = 'Explosion',
    [`WEAPON_RAMMED_BY_CAR`]        = 'Vehicle',
    [`WEAPON_RUN_OVER_BY_CAR`]      = 'Vehicle',
    [`WEAPON_VEHICLE_ROCKET`]       = 'Vehicle Rocket',
    [`WEAPON_ANIMAL`]               = 'Animal',
    [`WEAPON_COUGAR`]               = 'Cougar',
}
