-- release: the Hadolint release the Tools panel downloads when `hadolint` is not on the PATH.
-- Each platform's file is the program itself, pinned by its SHA-256 checksum, so a changed
-- file is refused. Hadolint publishes no file for Windows on ARM.

local VERSION = 'v2.15.1'
local BASE = 'https://github.com/hadolint/hadolint/releases/download/'
  .. VERSION
  .. '/'

---@type Proteus.ToolRelease
return {
  version = VERSION,
  from = 'github.com/hadolint/hadolint',
  assets = {
    ['windows-x86_64'] = {
      url = BASE .. 'hadolint-windows-x86_64.exe',
      sha256 = '01d927294962b5387f9ead4f18679158452be4f17c765ad0bdffe5264b9c7b0a',
    },
    ['linux-x86_64'] = {
      url = BASE .. 'hadolint-linux-x86_64',
      sha256 = 'c7187db94eeeeca956519a6af171adc31453941a1e777961f6e680f697c8c507',
    },
    ['linux-aarch64'] = {
      url = BASE .. 'hadolint-linux-arm64',
      sha256 = 'f6198ef8090f404dbb771abfee086eb8c48ac177f30da7fd3510aca35b344b5d',
    },
    ['macos-x86_64'] = {
      url = BASE .. 'hadolint-macos-x86_64',
      sha256 = 'ffe9bb18b23d5ed1eae50237aecdbb523d016e96da0bd4e7aa432040acfc3fde',
    },
    ['macos-aarch64'] = {
      url = BASE .. 'hadolint-macos-arm64',
      sha256 = '5c09f3213f8e40406abe048233d985eebef336d4a6a20021be47fadb6cf480a2',
    },
  },
}
