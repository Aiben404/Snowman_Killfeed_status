fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Snowman'
description 'Premium Admin Killfeed Status Viewer with Discord profile integration'
version '1.2.0'

shared_scripts {
    'vendor/vite_temp.js',
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/utils.lua',
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_config.lua',
    'server/discord.lua',
    'server/webhook.lua',
    'server/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js'
}

dependencies {
    'es_extended',
    'ox_lib'
}
