-- release: the Ruff release the Tools panel downloads when no Ruff is on the PATH. Each file
-- is pinned by its SHA-256 checksum. Ruff ships a `.zip` for Windows and a `.tar.gz` for Linux
-- and macOS, each holding the program in a folder.

local VERSION = '0.16.10'
local BASE = 'https://github.com/astral-sh/ruff/releases/download/'
  .. VERSION
  .. '/'

---@type Proteus.ToolRelease
return {
  version = VERSION,
  from = 'github.com/astral-sh/ruff',
  assets = {
    ['windows-x86_64'] = {
      url = BASE .. 'ruff-x86_64-pc-windows-msvc.zip',
      sha256 = '6b90457fbd249923db196044d5f3c26e4f7cefacc769c26fd52520fa033f736e',
      file = 'ruff.exe',
    },
    ['windows-aarch64'] = {
      url = BASE .. 'ruff-aarch64-pc-windows-msvc.zip',
      sha256 = 'cde60dbdf2697144474e6d87b8b51b73bb1fd218f4c180acb40abbd3b659d56f',
      file = 'ruff.exe',
    },
    ['linux-x86_64'] = {
      url = BASE .. 'ruff-x86_64-unknown-linux-gnu.tar.gz',
      sha256 = '9567ff1201e2fb3da31ff04c35587d768c66d6cb42dfa84de474e2bfe360b608',
      file = 'ruff',
    },
    ['linux-aarch64'] = {
      url = BASE .. 'ruff-aarch64-unknown-linux-gnu.tar.gz',
      sha256 = 'dc0d74de837ef0a7bcc62ce98c48a622b075d057161f13b958be2934becd55a6',
      file = 'ruff',
    },
    ['macos-x86_64'] = {
      url = BASE .. 'ruff-x86_64-apple-darwin.tar.gz',
      sha256 = 'ace641df42926e962cf04bc52c79eb6c50ba1ae6a17b602f081960616ecc1bd1',
      file = 'ruff',
    },
    ['macos-aarch64'] = {
      url = BASE .. 'ruff-aarch64-apple-darwin.tar.gz',
      sha256 = 'f051cd306de2691262a0574f8857cd1f4d6bfcd448084ea23d61b9c1c37df510',
      file = 'ruff',
    },
  },
}
