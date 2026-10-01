-- release: the Marksman release the Tools panel downloads when `marksman` is not on the PATH.
-- Each platform's file is pinned by its SHA-256 checksum, so a changed file is refused.
-- Marksman publishes the program itself, with no archive around it. One file runs on both
-- kinds of Mac. The release has no file for Windows on ARM, so that platform never downloads.

local VERSION = '2026-02-08'
local BASE = 'https://github.com/artempyanykh/marksman/releases/download/'
  .. VERSION
  .. '/'

local MAC = '6a801c17b5ac0dba69787c5282b3b3bd416e66c96253fae098d311c6bbd1833b'

---@type Proteus.ToolRelease
return {
  version = VERSION,
  from = 'github.com/artempyanykh/marksman',
  assets = {
    ['windows-x86_64'] = {
      url = BASE .. 'marksman.exe',
      sha256 = 'a6d05beb08ebe41b0a9f09c98a438540421436fa5531424c22e0bb1d22529705',
    },
    ['linux-x86_64'] = {
      url = BASE .. 'marksman-linux-x64',
      sha256 = 'be5098e8213219269c47fc0d916a66fa31ce0602ec967475c722260aabf26087',
    },
    ['linux-aarch64'] = {
      url = BASE .. 'marksman-linux-arm64',
      sha256 = 'db8e124527f7f8048e3e6c91821b9c52ef173d92c01e47d221bf1337afd962fb',
    },
    ['macos-x86_64'] = { url = BASE .. 'marksman-macos', sha256 = MAC },
    ['macos-aarch64'] = { url = BASE .. 'marksman-macos', sha256 = MAC },
  },
}
