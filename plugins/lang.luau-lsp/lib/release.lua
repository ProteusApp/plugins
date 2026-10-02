-- release: the luau-lsp release the Tools panel downloads when `luau-lsp` is not on the PATH.
-- Each platform's file is a zip that holds the program, pinned by its SHA-256 checksum, so a
-- changed file is refused. One file runs on both kinds of Mac. Windows on ARM has none.

local VERSION = '1.70.1'
local BASE = 'https://github.com/JohnnyMorganz/luau-lsp/releases/download/'
  .. VERSION
  .. '/'

---@type Proteus.ToolRelease
return {
  version = VERSION,
  from = 'github.com/JohnnyMorganz/luau-lsp',
  assets = {
    ['windows-x86_64'] = {
      url = BASE .. 'luau-lsp-win64.zip',
      sha256 = '64225b9738102a30de6ee09fb28e5a3827edc402ecf2a6364af570312468159f',
      file = 'luau-lsp.exe',
    },
    ['linux-x86_64'] = {
      url = BASE .. 'luau-lsp-linux-x86_64.zip',
      sha256 = '1a2ea1ae4f98f8946cefd970a4b54853e11ab4775e6932faa7f60cf920346567',
      file = 'luau-lsp',
    },
    ['linux-aarch64'] = {
      url = BASE .. 'luau-lsp-linux-arm64.zip',
      sha256 = '6062345b95124ca937b8c324b74bc3fddb1d6919ba133c58f8b17945ce1acbc2',
      file = 'luau-lsp',
    },
    ['macos-x86_64'] = {
      url = BASE .. 'luau-lsp-macos.zip',
      sha256 = '7d3936e8dec6dc77547abd061d2e950da392562a5f94858b880f23dba50d84cd',
      file = 'luau-lsp',
    },
    ['macos-aarch64'] = {
      url = BASE .. 'luau-lsp-macos.zip',
      sha256 = '7d3936e8dec6dc77547abd061d2e950da392562a5f94858b880f23dba50d84cd',
      file = 'luau-lsp',
    },
  },
}
