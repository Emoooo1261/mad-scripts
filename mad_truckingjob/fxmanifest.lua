fx_version 'cerulean'
game 'gta5'

description 'mad_truckingjob'
repository '-'
version '1.0.0'

shared_scripts {
	'@ox_lib/init.lua',
    '@qbx_core/modules/lib.lua',
}

client_scripts {
	'@qbx_core/modules/playerdata.lua',
	'client/main.lua',
	'client/boss.lua',
	'client/blip.lua'
}

server_scripts {
	'server/main.lua',
	'server/vehicle.lua',
	'server/queries.lua',
	'server/helper.lua',
	'@oxmysql/lib/MySQL.lua',
}

files {
	'config/server.lua',
	'config/shared.lua'
}

dependencies {
	'ox_lib',
	'ox_inventory',
	'oxmysql',
}

provide 'mad_truckingjob'
lua54 'yes'
use_experimental_fxv2_oal 'yes'