-- release: the Taplo release the Tools panel downloads when `taplo` is not on the PATH. Each
-- platform's file is pinned by its SHA-256 checksum, so a changed file is refused. The
-- release lists no checksums of its own, so these come from the files themselves.

local VERSION = '0.10.0'
local BASE = 'https://github.com/tamasfe/taplo/releases/download/'
  .. VERSION
  .. '/'

-- Each platform's file in the release, and its checksum. A platform without a checksum is
-- left out, so it never downloads.
local FILES = {
  ['windows-x86_64'] = {
    'taplo-windows-x86_64.gz',
    '550fdc955343f8a196447a05346ecf8827e391726e4ded577bb00a0a36cf220c',
  },
  ['windows-aarch64'] = {
    'taplo-windows-aarch64.gz',
    'c16a9a1248bdd746fde657b0196bfc47c8bede1e50ae73b7d9d33088a6682180',
  },
  ['linux-x86_64'] = {
    'taplo-linux-x86_64.gz',
    '8fe196b894ccf9072f98d4e1013a180306e17d244830b03986ee5e8eabeb6156',
  },
  ['linux-aarch64'] = {
    'taplo-linux-aarch64.gz',
    '033681d01eec8376c3fd38fa3703c79316f5e14bb013d859943b60a07bccdcc3',
  },
  ['macos-x86_64'] = {
    'taplo-darwin-x86_64.gz',
    '898122cde3a0b1cd1cbc2d52d3624f23338218c91b5ddb71518236a4c2c10ef2',
  },
  ['macos-aarch64'] = {
    'taplo-darwin-aarch64.gz',
    '713734314c3e71894b9e77513c5349835eefbd52908445a0d73b0c7dc469347d',
  },
}

local assets = {} ---@type table<string, Proteus.ToolAsset>
for platform, entry in pairs (FILES) do
  if entry[2] ~= '' then
    assets[platform] = { url = BASE .. entry[1], sha256 = entry[2] }
  end
end

---@type Proteus.ToolRelease
return { version = VERSION, from = 'github.com/tamasfe/taplo', assets = assets }
