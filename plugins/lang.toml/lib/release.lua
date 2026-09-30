-- release: the Taplo release the Tools panel downloads when `taplo` is not on the PATH. Each
-- platform's file is pinned by its SHA-256 checksum, so a changed file is refused.

local VERSION = '0.10.0'
local BASE = 'https://github.com/tamasfe/taplo/releases/download/'
  .. VERSION
  .. '/'

-- Each platform's file in the release, and its checksum. A platform without a checksum is
-- left out, so it never downloads.
local FILES = {
  ['windows-x86_64'] = { 'taplo-windows-x86_64.gz', '' },
  ['windows-aarch64'] = { 'taplo-windows-aarch64.gz', '' },
  ['linux-x86_64'] = { 'taplo-linux-x86_64.gz', '' },
  ['linux-aarch64'] = { 'taplo-linux-aarch64.gz', '' },
  ['macos-x86_64'] = { 'taplo-darwin-x86_64.gz', '' },
  ['macos-aarch64'] = { 'taplo-darwin-aarch64.gz', '' },
}

local assets = {} ---@type table<string, Proteus.ToolAsset>
for platform, entry in pairs (FILES) do
  if entry[2] ~= '' then
    assets[platform] = { url = BASE .. entry[1], sha256 = entry[2] }
  end
end

---@type Proteus.ToolRelease
return { version = VERSION, from = 'github.com/tamasfe/taplo', assets = assets }
