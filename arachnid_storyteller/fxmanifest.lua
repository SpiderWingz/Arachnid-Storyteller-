fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

author 'Arachnid'
description 'Arachnid Storyteller — a RedM gamemaster story and scene planning console'
version '0.1.0'

shared_script 'config.lua'
client_script 'client.lua'
server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server.lua'
}

ui_page 'html/index.html'
files {
  'html/index.html'
}
