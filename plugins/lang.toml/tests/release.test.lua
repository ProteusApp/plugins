local release = require ('lib.release') --[[@as Proteus.ToolRelease]]

test ('every Taplo download is an https file pinned by its checksum', function ()
  ok (release.version:match ('^%d+%.%d+%.%d+$'), release.version)
  local platforms = {} ---@type string[]
  for platform, asset in pairs (release.assets) do
    platforms[#platforms + 1] = platform
    ok (
      asset.url:match ('^https://github%.com/tamasfe/taplo/releases/download/'),
      asset.url
    )
    ok (asset.url:find (release.version, 1, true), asset.url)
    ok (asset.sha256:match ('^%x+$') and #asset.sha256 == 64, platform)
  end
  table.sort (platforms)
  eq (platforms, {
    'linux-aarch64',
    'linux-x86_64',
    'macos-aarch64',
    'macos-x86_64',
    'windows-aarch64',
    'windows-x86_64',
  })
end)
