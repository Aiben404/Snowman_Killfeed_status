--[[
    Snowman Killfeed Status - Server-only secrets
    Author: Snowman

    This file is loaded ONLY on the server (see fxmanifest server_scripts) and is
    NEVER sent to clients, unlike the shared config.lua. Keep the Discord bot
    token here so it can never be extracted from a connected client.

    Two ways to provide the token (the convar wins when set):

      1. Convar (in server.cfg):
            set killfeed_discord_token "YOUR_DISCORD_BOT_TOKEN_HERE"
         The resource reads it once on start and then WIPES the convar from
         memory (see below), so it can't be printed back in the console.

      2. Inline fallback below (this file is server-only — do NOT commit a real
         token to a public repo).

    NOTE: If you use the convar method and restart ONLY this resource, the convar
    was already wiped, so re-run the `set` line or do a full server restart.
    The inline method does not have this caveat.
]]

Config = Config or {}
Config.Discord = Config.Discord or {}

-- Inline fallback. Leave as the placeholder if you use the convar instead.
local INLINE_TOKEN = 'YOUR_DISCORD_BOT_TOKEN_HERE'

-- Prefer the convar; fall back to the inline value.
local convarToken = GetConvar('killfeed_discord_token', '')
Config.Discord.BotToken = (convarToken ~= '' and convarToken) or INLINE_TOKEN

-- SECURITY: now that the token lives in server-side Lua memory
-- (Config.Discord.BotToken, which is never sent to clients), wipe the convar so
-- typing `killfeed_discord_token` in the server console — or any command
-- executor — can no longer reveal the secret.
if convarToken ~= '' then
    SetConvar('killfeed_discord_token', '')
end

----------------------------------------------------------------------
-- DISCORD WEBHOOK URL (optional private override)
----------------------------------------------------------------------
-- The webhook URL can be set directly in config.lua (Config.Webhook.Url).
-- If you prefer to keep it private (out of the client-downloadable config),
-- provide it here or via the convar instead — either one OVERRIDES config.lua.
-- The convar is wiped after being read so it can't be printed in the console.
--
--     set killfeed_webhook_url "https://discord.com/api/webhooks/XXX/YYY"
Config.Webhook = Config.Webhook or {}

local INLINE_WEBHOOK = ''   -- leave empty to use the value from config.lua

local convarWebhook = GetConvar('killfeed_webhook_url', '')
if convarWebhook ~= '' then
    Config.Webhook.Url = convarWebhook
    SetConvar('killfeed_webhook_url', '')   -- wipe so it can't be read back
elseif INLINE_WEBHOOK ~= '' then
    Config.Webhook.Url = INLINE_WEBHOOK
end
-- else: keep whatever config.lua provided.
