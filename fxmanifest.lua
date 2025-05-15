fx_version 'cerulean'
game 'gta5'
author 'CodineDev (https://github.com/xciphertv)'
description 'CDN-Fuel - Refactored with OX Libraries'
version '3.0.0'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/*.lua'
}

client_scripts {
    'client/*.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/*.lua'
}

dependencies {
    'oxmysql',
    'ox_lib',
    'ox_inventory',
    'ox_target'
}

data_file 'DLC_ITYP_REQUEST' 'stream/[electric_nozzle]/electric_nozzle_typ.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/[electric_charger]/electric_charger_typ.ytyp'

provide 'cdn-syphoning'