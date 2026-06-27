--[[
    Snowman Killfeed Status
    Author: Snowman

    Premium Admin Killfeed Viewer for ESX with a Discord-inspired NUI and
    real Discord profile integration via a bot token.

    Every value below is documented. Nothing here needs the database unless you
    explicitly enable persistence (Config.Database.Enabled).
]]

Config = {}

----------------------------------------------------------------------
-- GENERAL
----------------------------------------------------------------------
Config.Command          = 'killfeed'          -- /killfeed command name
Config.Locale           = 'en'                 -- reserved for future locale support
Config.Debug            = false                -- prints verbose logs server + client

-- ESX groups that are allowed to open the killfeed.
-- Any group present here (xPlayer.getGroup()) grants access.
Config.AllowedGroups    = {
    ['superadmin'] = true,
    ['admin']      = true,
    ['mod']        = true,
}

----------------------------------------------------------------------
-- HISTORY
----------------------------------------------------------------------
Config.MaxHistory       = 60   -- maximum kills kept in memory (oldest auto-deleted)

----------------------------------------------------------------------
-- ON-SCREEN KILLFEED
----------------------------------------------------------------------
-- When a kill occurs, a real game-style killfeed entry slides onto the
-- screen and fades out on its own. No input focus is taken, so gameplay is
-- never interrupted. This replaces the old ox_lib toast notification.
-- NOTE: Position and on/off are also adjustable per-admin from the gear menu
-- inside the killfeed panel. Those personal choices are saved locally and
-- override the defaults below for that admin.
Config.Killfeed = {
    Enabled  = true,
    Position = 'top-right',   -- DEFAULT corner (top-right | top-left | bottom-right | bottom-left)
    MaxShown = 5,             -- max entries visible on screen at once
    Duration = 6000,          -- ms an entry stays before fading out
    ShowAvatars = true,       -- show Discord avatars next to names
    ShowDistance = true,      -- show the kill distance chip

    -- Who sees the killfeed:
    --   'admins'   = only players in Config.AllowedGroups (admin tool, default)
    --   'everyone' = every player on the server (public server killfeed)
    Audience = 'admins',
}

----------------------------------------------------------------------
-- NOTIFICATIONS (admin action feedback only)
----------------------------------------------------------------------
-- Small ox_lib toasts used for admin-action results (heal sent, target
-- offline, permission denied, …). Kill events use Config.Killfeed above.
Config.Notifications = {
    Enabled  = true,
    Position = 'top-right',   -- ox_lib notify position
    Duration = 4000,          -- ms
}

----------------------------------------------------------------------
-- DISCORD WEBHOOK LOGS
----------------------------------------------------------------------
-- Sends clean embed logs to a Discord channel via webhook.
--
-- Paste your webhook URL below for the simplest setup.
-- NOTE: config.lua is a shared_script, so a URL set here is technically
-- downloadable by clients. If you prefer to keep it private, leave Url = ''
-- here and set it in the server-only file  server/sv_config.lua  (or the
-- `killfeed_webhook_url` convar) — that value overrides this one.
Config.Webhook = {
    Enabled         = true,
    Url             = '',               -- https://discord.com/api/webhooks/XXX/YYY
    Username        = 'Killfeed Logs',  -- name the webhook posts under
    Avatar          = '',               -- optional avatar URL for the webhook

    -- What to log
    LogKills        = true,             -- every kill
    LogAdminActions = true,             -- teleport / bring / heal / revive
    LogPanelOpen    = false,            -- when an admin opens /killfeed

    -- Only log player-vs-player kills (skip suicides / environment deaths).
    KillsPlayerOnly = false,

    -- Include identifiers (Discord mention, license, server id) on kill logs.
    IncludeIdentifiers = true,

    -- Embed accent colours (hex).
    Colors = {
        kill  = 0xE0626F,
        admin = 0x6E9BEF,
        info  = 0x58BD92,
    },
}

----------------------------------------------------------------------
-- DATABASE (OPTIONAL)
----------------------------------------------------------------------
-- Memory is always used. If Enabled = true, kills are also persisted to MySQL
-- and the last Config.MaxHistory rows are loaded on resource start.
Config.Database = {
    Enabled = false,
    Table   = 'snowman_killfeed',
}

----------------------------------------------------------------------
-- DISCORD BOT INTEGRATION
----------------------------------------------------------------------
-- Fetch REAL Discord profile data (username, display name, avatar, banner).
-- The bot does NOT need to share a guild with the user for /users/{id} lookups
-- — only a valid bot token is required.
--
-- SECURITY: The bot token is intentionally NOT in this file. config.lua is a
-- shared_script and would be downloaded by every client. Put the token in the
-- server-only file  server/sv_config.lua  (or the `killfeed_discord_token`
-- convar). See that file for details.
Config.Discord = {
    Enabled       = true,
    BotToken      = '',     -- DO NOT set here — overridden by server/sv_config.lua
    CacheMinutes  = 30,     -- how long a fetched profile stays cached
    AvatarSize    = 512,    -- requested avatar size (power of two, 16..4096)
    BannerSize    = 1024,   -- requested banner size

    -- Fallbacks used when the player has no linked Discord or the API fails.
    -- Never overrides real data when it is available.
    DefaultAvatar = 'https://cdn.discordapp.com/embed/avatars/0.png',
    DefaultBanner = '', -- empty string => CSS gradient placeholder banner
}

----------------------------------------------------------------------
-- WEAPON CLASSIFICATION
----------------------------------------------------------------------
-- Maps weapon hashes to a category used for filters + icons.
-- Categories: pistol, smg, shotgun, ar, sniper, knife, melee, explosion,
--             vehicle, fire, unknown
-- Add server-specific / custom weapons here.
Config.WeaponCategories = {
    -- Pistols
    [`WEAPON_PISTOL`]           = 'pistol',
    [`WEAPON_PISTOL_MK2`]       = 'pistol',
    [`WEAPON_COMBATPISTOL`]     = 'pistol',
    [`WEAPON_APPISTOL`]         = 'pistol',
    [`WEAPON_PISTOL50`]         = 'pistol',
    [`WEAPON_SNSPISTOL`]        = 'pistol',
    [`WEAPON_SNSPISTOL_MK2`]    = 'pistol',
    [`WEAPON_HEAVYPISTOL`]      = 'pistol',
    [`WEAPON_VINTAGEPISTOL`]    = 'pistol',
    [`WEAPON_MARKSMANPISTOL`]   = 'pistol',
    [`WEAPON_REVOLVER`]         = 'pistol',
    [`WEAPON_REVOLVER_MK2`]     = 'pistol',
    [`WEAPON_DOUBLEACTION`]     = 'pistol',
    [`WEAPON_CERAMICPISTOL`]    = 'pistol',
    [`WEAPON_NAVYREVOLVER`]     = 'pistol',
    [`WEAPON_STUNGUN`]          = 'pistol',
    [`WEAPON_FLAREGUN`]         = 'pistol',

    -- SMG
    [`WEAPON_MICROSMG`]         = 'smg',
    [`WEAPON_SMG`]              = 'smg',
    [`WEAPON_SMG_MK2`]          = 'smg',
    [`WEAPON_ASSAULTSMG`]       = 'smg',
    [`WEAPON_COMBATPDW`]        = 'smg',
    [`WEAPON_MACHINEPISTOL`]    = 'smg',
    [`WEAPON_MINISMG`]          = 'smg',

    -- Shotguns
    [`WEAPON_PUMPSHOTGUN`]      = 'shotgun',
    [`WEAPON_PUMPSHOTGUN_MK2`]  = 'shotgun',
    [`WEAPON_SAWNOFFSHOTGUN`]   = 'shotgun',
    [`WEAPON_BULLPUPSHOTGUN`]   = 'shotgun',
    [`WEAPON_ASSAULTSHOTGUN`]   = 'shotgun',
    [`WEAPON_HEAVYSHOTGUN`]     = 'shotgun',
    [`WEAPON_DBSHOTGUN`]        = 'shotgun',
    [`WEAPON_AUTOSHOTGUN`]      = 'shotgun',
    [`WEAPON_COMBATSHOTGUN`]    = 'shotgun',

    -- Assault Rifles
    [`WEAPON_ASSAULTRIFLE`]       = 'ar',
    [`WEAPON_ASSAULTRIFLE_MK2`]   = 'ar',
    [`WEAPON_CARBINERIFLE`]       = 'ar',
    [`WEAPON_CARBINERIFLE_MK2`]   = 'ar',
    [`WEAPON_ADVANCEDRIFLE`]      = 'ar',
    [`WEAPON_SPECIALCARBINE`]     = 'ar',
    [`WEAPON_SPECIALCARBINE_MK2`] = 'ar',
    [`WEAPON_BULLPUPRIFLE`]       = 'ar',
    [`WEAPON_BULLPUPRIFLE_MK2`]   = 'ar',
    [`WEAPON_COMPACTRIFLE`]       = 'ar',
    [`WEAPON_MILITARYRIFLE`]      = 'ar',
    [`WEAPON_HEAVYRIFLE`]         = 'ar',
    [`WEAPON_TACTICALRIFLE`]      = 'ar',
    [`WEAPON_MG`]                 = 'ar',
    [`WEAPON_COMBATMG`]           = 'ar',
    [`WEAPON_COMBATMG_MK2`]       = 'ar',
    [`WEAPON_GUSENBERG`]          = 'ar',

    -- Snipers
    [`WEAPON_SNIPERRIFLE`]        = 'sniper',
    [`WEAPON_HEAVYSNIPER`]        = 'sniper',
    [`WEAPON_HEAVYSNIPER_MK2`]    = 'sniper',
    [`WEAPON_MARKSMANRIFLE`]      = 'sniper',
    [`WEAPON_MARKSMANRIFLE_MK2`]  = 'sniper',
    [`WEAPON_PRECISIONRIFLE`]     = 'sniper',

    -- Knives / Melee (sharp)
    [`WEAPON_KNIFE`]            = 'knife',
    [`WEAPON_DAGGER`]           = 'knife',
    [`WEAPON_SWITCHBLADE`]      = 'knife',
    [`WEAPON_MACHETE`]          = 'knife',
    [`WEAPON_HATCHET`]          = 'knife',
    [`WEAPON_KNUCKLE`]          = 'melee',
    [`WEAPON_BOTTLE`]           = 'knife',

    -- Melee (blunt)
    [`WEAPON_BAT`]              = 'melee',
    [`WEAPON_CROWBAR`]          = 'melee',
    [`WEAPON_GOLFCLUB`]         = 'melee',
    [`WEAPON_HAMMER`]           = 'melee',
    [`WEAPON_NIGHTSTICK`]       = 'melee',
    [`WEAPON_WRENCH`]           = 'melee',
    [`WEAPON_BATTLEAXE`]        = 'melee',
    [`WEAPON_POOLCUE`]          = 'melee',
    [`WEAPON_FLASHLIGHT`]       = 'melee',
    [`WEAPON_STONE_HATCHET`]    = 'melee',
    [`WEAPON_UNARMED`]          = 'melee',

    -- Explosives
    [`WEAPON_GRENADE`]                = 'explosion',
    [`WEAPON_STICKYBOMB`]             = 'explosion',
    [`WEAPON_PROXMINE`]               = 'explosion',
    [`WEAPON_PIPEBOMB`]               = 'explosion',
    [`WEAPON_RPG`]                    = 'explosion',
    [`WEAPON_GRENADELAUNCHER`]        = 'explosion',
    [`WEAPON_GRENADELAUNCHER_SMOKE`]  = 'explosion',
    [`WEAPON_HOMINGLAUNCHER`]         = 'explosion',
    [`WEAPON_COMPACTLAUNCHER`]        = 'explosion',
    [`WEAPON_RAILGUN`]                = 'explosion',
    [`WEAPON_VEHICLE_ROCKET`]         = 'explosion',
    [`WEAPON_AIR_DEFENCE_GUN`]        = 'explosion',

    -- Fire
    [`WEAPON_MOLOTOV`]          = 'fire',
    [`WEAPON_PETROLCAN`]        = 'fire',
    [`WEAPON_FIREWORK`]         = 'fire',
    [`WEAPON_FLARE`]            = 'fire',
    [`WEAPON_HAZARDCAN`]        = 'fire',
}

-- Death-type categories (used when there is no weapon, e.g. environment deaths).
-- These map our internal cause strings to a category for icon/filter use.
Config.DeathTypeCategory = {
    vehicle  = 'vehicle',
    fall     = 'unknown',
    drown    = 'unknown',
    fire     = 'fire',
    explosion= 'explosion',
    suicide  = 'unknown',
    animal   = 'unknown',
    unknown  = 'unknown',
}

-- Font Awesome icon per category (rendered in the UI).
Config.CategoryIcons = {
    pistol    = 'fa-solid fa-gun',
    smg       = 'fa-solid fa-gun',
    shotgun   = 'fa-solid fa-burst',
    ar        = 'fa-solid fa-crosshairs',
    sniper    = 'fa-solid fa-bullseye',
    knife     = 'fa-solid fa-utensils',
    melee     = 'fa-solid fa-hand-fist',
    explosion = 'fa-solid fa-bomb',
    vehicle   = 'fa-solid fa-car-burst',
    fire      = 'fa-solid fa-fire',
    unknown   = 'fa-solid fa-skull',
}

----------------------------------------------------------------------
-- ADMIN ACTION EVENTS
----------------------------------------------------------------------
-- The profile panel exposes admin buttons. Each one triggers the configurable
-- SERVER event named below. This lets you wire actions into your own admin
-- framework instead of forcing a built-in implementation.
--
-- Built-in lightweight handlers are provided in server/main.lua for teleport,
-- bring, heal and revive; set UseBuiltIn = false to fully delegate to your
-- own events.
Config.AdminActions = {
    UseBuiltIn = true,

    Events = {
        teleportToKiller = 'snowman_killfeed:admin:teleport',
        teleportToVictim = 'snowman_killfeed:admin:teleport',
        bringKiller      = 'snowman_killfeed:admin:bring',
        bringVictim      = 'snowman_killfeed:admin:bring',
        heal             = 'snowman_killfeed:admin:heal',
        revive           = 'snowman_killfeed:admin:revive',
    },
}

----------------------------------------------------------------------
-- THEME (passed to the UI so colours can be tuned from one place)
----------------------------------------------------------------------
-- Minimal flat palette. Keep colours muted for readability; the UI relies on
-- whitespace and hairlines rather than bright fills.
Config.Theme = {
    bg        = '#0e0f12',
    panel     = '#14161a',
    card      = '#191c21',
    cardHover = '#20242b',
    accent    = '#6e9bef',
    success   = '#58bd92',
    danger    = '#e0626f',
    warning   = '#d8b15a',
}
