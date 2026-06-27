# Killfeed Status

A premium **admin killfeed** for **ESX** servers, featuring a clean, minimal NUI panel, a real on-screen killfeed HUD, live Discord profile integration, Discord webhook logging, and built-in admin actions.

Idle cost is effectively **0.00ms** — death detection is fully event-driven, with no per-frame loops.

---

## ✨ Features

- **Minimal admin panel** (`/killfeed`) — flat, readable dark UI with a searchable, filterable kill list and a detailed player profile.
- **On-screen killfeed HUD** — game-style kill entries that slide into a screen corner and fade out. Takes **no input focus**, so gameplay is never interrupted.
- **Per-admin HUD settings** — each admin can toggle the HUD on/off and pick its corner from a gear menu inside the panel. Saved locally per admin.
- **Live Discord profiles** — real usernames, display names, and avatars via a Discord bot token (cached).
- **Discord webhook logs** — clean embeds for kills, admin actions, and panel opens.
- **Built-in admin actions** — teleport to killer/victim, bring killer/victim, heal, revive (all delegatable to your own framework).
- **Session stats** — kills, deaths, and headshots tracked per license in memory.
- **Optional MySQL persistence** — survive restarts and reload recent kills on boot.
- **Secret-safe** — bot token and webhook URL are kept out of the client-downloadable config, with optional convar storage that is wiped after read.

---

## 📦 Dependencies

| Resource | Required | Purpose |
|---|---|---|
| [es_extended](https://github.com/esx-framework/esx_core) | ✅ | ESX framework (player data, groups) |
| [ox_lib](https://github.com/overextended/ox_lib) | ✅ | Notifications + callbacks |
| [oxmysql](https://github.com/overextended/oxmysql) | ⛔ optional | Only if `Config.Database.Enabled = true` |

> Ensure `ox_lib` (and `es_extended`) start **before** this resource in your `server.cfg`.

---

## 🚀 Installation

1. Drop the `Snowman_Killfeed_status` folder into your resources (e.g. `resources/[scripts]/`).
2. Add to your `server.cfg`:
   ```cfg
   ensure es_extended
   ensure ox_lib
   ensure oxmysql        # only if you enable the database
   ensure Snowman_Killfeed_status
   ```
3. Configure the Discord bot token (see [Discord setup](#-discord-bot-setup)).
4. (Optional) Set a webhook URL for logging (see [Webhook logs](#-discord-webhook-logs)).
5. Restart the server.

---

## 🔐 Permissions

Only players in an allowed ESX group can open the killfeed and use admin actions.

```lua
Config.AllowedGroups = {
    ['superadmin'] = true,
    ['admin']      = true,
    ['mod']        = true,
}
```

Open the panel in-game with:
```
/killfeed
```

---

## 🖥️ The Admin Panel

- **Search** — name, Discord, license, or weapon.
- **Filter** — by weapon category (pistol, SMG, sniper, explosion, vehicle, etc.).
- **Kill list** — newest first, up to `Config.MaxHistory` entries.
- **Player profile** — avatar, status, and:
  - **Statistics** — Kills, Deaths, Headshots.
  - **Player Info** — Discord ID, license, ping, job, money, bank, character, health, armor, vehicle, weapon, plus **killer & victim death coordinates**.
  - **Kill Details** — side-by-side killer vs victim (click a side to inspect that player).
  - **Timeline** — recent kills in context.
  - **Admin Actions** — teleport, bring, heal, revive.
- **Gear menu (⚙)** — per-admin killfeed HUD settings (on/off + corner).

---

## 🎯 On-Screen Killfeed HUD

Configured under `Config.Killfeed`:

```lua
Config.Killfeed = {
    Enabled      = true,
    Position     = 'top-right',  -- top-right | top-left | bottom-right | bottom-left
    MaxShown     = 5,            -- max entries on screen at once
    Duration     = 6000,         -- ms before an entry fades
    ShowAvatars  = true,
    ShowDistance = true,
    Audience     = 'admins',     -- 'admins' (tool) or 'everyone' (public killfeed)
}
```

- **`Audience = 'admins'`** — only admins see the HUD (default; admin tool).
- **`Audience = 'everyone'`** — every player sees it (public server killfeed).

Each admin can override the position/visibility from the in-panel gear menu; those personal choices are saved in NUI `localStorage` and win over the defaults above.

---

## 🤖 Discord Bot Setup

Real Discord profiles (username, display name, avatar) require a bot token. The bot **does not** need to share a guild with the player.

1. Create an application + bot at the [Discord Developer Portal](https://discord.com/developers/applications).
2. Copy the **bot token**.
3. Provide it using **one** of these (both keep the token off clients):

   **Option A — inline (recommended for frequent resource restarts):**
   In [`server/sv_config.lua`](server/sv_config.lua):
   ```lua
   local INLINE_TOKEN = 'your_bot_token_here'
   ```

   **Option B — convar:** in `server.cfg`:
   ```cfg
   set killfeed_discord_token "your_bot_token_here"
   ```

> **Security:** The convar is **wiped from memory after the resource reads it**, so typing `killfeed_discord_token` in the console no longer reveals it.
>
> ⚠️ **Caveat:** because the convar is wiped, restarting **only the resource** loses it (the `set` line only runs on a full server start). If you restart the resource often, use **Option A (inline)** instead.

### Diagnosing "Unknown User"

If profiles show **Unknown User** with the default avatar, run in-game:
```
/killfeed_discordtest
```
It prints to the **server console**: your Discord identifier, the bot-token state, and the fetch result. Common causes:

| Symptom | Cause | Fix |
|---|---|---|
| `discord identifier: NONE` | Player has no Discord linked | Have the **Discord desktop app running** when connecting |
| `bot token: NOT SET` | Convar wiped by a resource-only restart | Use inline token, or full server restart |
| `HTTP 401` (with `Config.Debug`) | Invalid/expired token | Set the correct token |

Set `Config.Debug = true` for detailed HTTP reasons in the console.

---

## 📝 Discord Webhook Logs

Sends clean embed logs to a Discord channel. Configured under `Config.Webhook`:

```lua
Config.Webhook = {
    Enabled            = true,
    Url                = '',            -- https://discord.com/api/webhooks/XXX/YYY
    Username           = 'Killfeed Logs',
    Avatar             = '',
    LogKills           = true,
    LogAdminActions    = true,
    LogPanelOpen       = false,
    KillsPlayerOnly    = false,         -- skip suicides/environment deaths
    IncludeIdentifiers = true,          -- mention/license/id on kill logs
    Colors = { kill = 0xE0626F, admin = 0x6E9BEF, info = 0x58BD92 },
}
```

**Webhook URL** — paste it into `Config.Webhook.Url`, or keep it private by setting it in [`server/sv_config.lua`](server/sv_config.lua) (`INLINE_WEBHOOK`) or the `killfeed_webhook_url` convar (server values override config.lua and are wiped after read).

> A Discord webhook is rate-limited to ~30 requests/minute. On very busy servers, set `KillsPlayerOnly = true` or `LogKills = false`.

---

## 🛠️ Admin Actions

The profile panel exposes built-in actions. Each one also fires a configurable server event so you can hook your own framework.

```lua
Config.AdminActions = {
    UseBuiltIn = true,                  -- false = fully delegate to your events
    Events = {
        teleportToKiller = 'snowman_killfeed:admin:teleport',
        teleportToVictim = 'snowman_killfeed:admin:teleport',
        bringKiller      = 'snowman_killfeed:admin:bring',
        bringVictim      = 'snowman_killfeed:admin:bring',
        heal             = 'snowman_killfeed:admin:heal',
        revive           = 'snowman_killfeed:admin:revive',
    },
}
```

Built-in handlers cover teleport, bring, and heal directly; revive tries common ESX/hospital revive events. Set `UseBuiltIn = false` to route everything through your own events.

---

## 🗄️ Optional Database Persistence

Kills always live in memory. Enable MySQL to survive restarts:

```lua
Config.Database = {
    Enabled = true,
    Table   = 'snowman_killfeed',
}
```

The table is created automatically on first start, and the most recent `Config.MaxHistory` kills are reloaded on boot. Requires `oxmysql`.

---

## 🎨 Theme

Colours are tunable from one place and pushed to the UI live:

```lua
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
```

---

## ⌨️ Commands

| Command | Who | Description |
|---|---|---|
| `/killfeed` | Allowed groups | Open the admin killfeed panel |
| `/killfeed_discordtest` | Allowed groups | Print Discord diagnostics to the server console |

---

## 📁 Structure

```
Snowman_Killfeed_status/
├── config.lua              # Shared config (no secrets)
├── fxmanifest.lua
├── client/
│   ├── main.lua            # Death detection, NUI bridge, admin results
│   └── utils.lua           # Weapon labels, cause classification
├── server/
│   ├── sv_config.lua       # Server-only secrets (bot token, webhook URL)
│   ├── discord.lua         # Discord profile fetching + cache
│   ├── webhook.lua         # Discord webhook logging
│   └── main.lua            # Kill handling, stats, admin actions, commands
└── html/                   # NUI (index.html, style.css, script.js)
```

---

## ❓ Troubleshooting

- **ox_lib notifications not showing** — ensure `ox_lib` starts before this resource and there are no load errors. The script falls back to native notifications if ox_lib is unavailable.
- **Profiles show "Unknown User"** — run `/killfeed_discordtest` (see [diagnosing](#diagnosing-unknown-user)).
- **HUD frozen / can't move** — fixed; always run the latest `html/script.js`.
- **Token revealed in console** — set it inline in `server/sv_config.lua`, or via the convar (which is wiped after read).

---

## 📄 Credits

Author: **Snowman**
