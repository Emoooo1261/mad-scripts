fx_version 'cerulean'
game 'gta5'

description 'Trailer Door Interaction'
version '0.0.0'


shared_script {
    '@ox_lib/init.lua',
}

client_script {
    'client/main.lua'
}

server_script {
    'server/main.lua'
}

files {
    'config/shared.lua'
}

dependencies {
    'ox_lib',
    'ox_target'
}

provide 'mad_trailerdoors'
lua54 'yes'
use_experimental_fxv2_oal 'yes'