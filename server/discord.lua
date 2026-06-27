--[[
    Snowman Killfeed Status - Discord Integration
    Author: Snowman

    Fetches REAL Discord profile data (username, display name, avatar, banner)
    through a bot token and caches it. Never overrides real data with a
    placeholder when the API succeeds.

    Endpoint used: GET https://discord.com/api/v10/users/{user.id}
    Requires only a valid bot token (no shared guild necessary).
]]

Discord = {}

-- profileCache[discordId] = { data = <profile>, expires = <os.time> }
local profileCache = {}

----------------------------------------------------------------------
-- Identifier resolution
----------------------------------------------------------------------

-- Returns the raw numeric Discord id for a connected player, or nil.
function Discord.GetId(serverId)
    if not serverId then return nil end
    for _, id in ipairs(GetPlayerIdentifiers(serverId) or {}) do
        if id:sub(1, 8) == 'discord:' then
            return id:sub(9)
        end
    end
    return nil
end

----------------------------------------------------------------------
-- Profile building helpers
----------------------------------------------------------------------

-- Builds the CDN avatar URL, honouring animated (a_) hashes.
local function buildAvatarUrl(id, hash)
    if not hash then return nil end
    local ext = hash:sub(1, 2) == 'a_' and 'gif' or 'png'
    return ('https://cdn.discordapp.com/avatars/%s/%s.%s?size=%d')
        :format(id, hash, ext, Config.Discord.AvatarSize)
end

-- Builds the CDN banner URL (animated when available).
local function buildBannerUrl(id, hash)
    if not hash then return nil end
    local ext = hash:sub(1, 2) == 'a_' and 'gif' or 'png'
    return ('https://cdn.discordapp.com/banners/%s/%s.%s?size=%d')
        :format(id, hash, ext, Config.Discord.BannerSize)
end

-- A graceful fallback profile (used when no Discord linked or API failure).
function Discord.Fallback(discordId)
    return {
        id          = discordId,
        username    = 'Unknown User',
        displayName = nil,
        avatarUrl   = Config.Discord.DefaultAvatar,
        bannerUrl   = Config.Discord.DefaultBanner ~= '' and Config.Discord.DefaultBanner or nil,
        bannerColor = nil,
        accentColor = nil,
        isReal      = false,
    }
end

-- Transforms a raw Discord API user object into our compact profile shape.
local function buildProfile(data)
    local id = data.id
    local avatarUrl = buildAvatarUrl(id, data.avatar) or Config.Discord.DefaultAvatar
    local bannerUrl = buildBannerUrl(id, data.banner)

    -- Discord encodes accent_color as a 24-bit int.
    local accentColor = nil
    if data.accent_color then
        accentColor = ('#%06X'):format(data.accent_color)
    end

    return {
        id          = id,
        username    = data.username,
        displayName = data.global_name,        -- the "Display Name"
        avatarUrl   = avatarUrl,
        bannerUrl   = bannerUrl,                -- may be nil -> UI uses accent/gradient
        bannerColor = bannerUrl == nil and accentColor or nil,
        accentColor = accentColor,
        isReal      = true,
    }
end

----------------------------------------------------------------------
-- Fetching (cached, blocking via promise — call from a thread)
----------------------------------------------------------------------

-- Returns a profile table for the given discord id. Uses cache when fresh.
-- MUST be called from within a coroutine/thread (all net events qualify).
function Discord.FetchProfile(discordId)
    if not Config.Discord.Enabled then
        return Discord.Fallback(discordId)
    end

    if not discordId then
        if Config.Debug then
            print('[snowman_killfeed] No discord identifier for this player (they must have the '
                .. 'Discord desktop app running when connecting). Using fallback profile.')
        end
        return Discord.Fallback(discordId)
    end

    if not Config.Discord.BotToken or Config.Discord.BotToken == ''
        or Config.Discord.BotToken == 'YOUR_DISCORD_BOT_TOKEN_HERE' then
        if Config.Debug then
            print('[snowman_killfeed] Discord bot token not configured — using fallback profile.')
        end
        return Discord.Fallback(discordId)
    end

    local cached = profileCache[discordId]
    if cached and cached.expires > os.time() then
        return cached.data
    end

    local p = promise.new()
    PerformHttpRequest('https://discord.com/api/v10/users/' .. discordId, function(status, body)
        if status == 200 and body then
            local ok, data = pcall(json.decode, body)
            if ok and data and data.id then
                local profile = buildProfile(data)
                profileCache[discordId] = {
                    data    = profile,
                    expires = os.time() + (Config.Discord.CacheMinutes * 60),
                }
                if Config.Debug then
                    print(('[snowman_killfeed] Discord OK for %s -> %s'):format(discordId, tostring(profile.username)))
                end
                p:resolve(profile)
                return
            end
        end

        if Config.Debug then
            local hint = ''
            if status == 401 then hint = '  (HTTP 401 = invalid/expired bot token — re-check killfeed_discord_token)'
            elseif status == 404 then hint = '  (HTTP 404 = no Discord user with that id)'
            elseif status == 429 then hint = '  (HTTP 429 = rate limited by Discord)'
            elseif status == 0 then hint = '  (HTTP 0 = request blocked/no response — check server internet/firewall)' end
            print(('[snowman_killfeed] Discord fetch failed for %s (HTTP %s)%s'):format(tostring(discordId), tostring(status), hint))
        end
        -- Cache the fallback briefly to avoid hammering the API on repeat misses.
        local fallback = Discord.Fallback(discordId)
        profileCache[discordId] = { data = fallback, expires = os.time() + 60 }
        p:resolve(fallback)
    end, 'GET', '', {
        ['Authorization'] = 'Bot ' .. Config.Discord.BotToken,
        ['Content-Type']  = 'application/json',
    })

    return Citizen.Await(p)
end

-- Convenience: fetch directly from a server id.
function Discord.FetchForPlayer(serverId)
    return Discord.FetchProfile(Discord.GetId(serverId))
end

-- Clears cached profiles (exposed for admin tooling / debugging).
function Discord.ClearCache()
    profileCache = {}
end
