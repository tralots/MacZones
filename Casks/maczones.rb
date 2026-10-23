cask "maczones" do
  version "1.0.1"
  sha256 "a1e3a9a02796011bd908cb9467a0367bf1b4eb039112c94191a040fe171cfa06"

  url "https://github.com/tralots/MacZones/releases/download/v#{version}/MacZones-#{version}.zip"
  name "MacZones"
  desc "Window snapping: hold Shift while dragging a window to snap it into zones"
  homepage "https://github.com/tralots/MacZones"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "MacZones.app"

  uninstall quit: "com.edijs.MacZones"

  zap trash: [
    "~/Library/Application Support/MacZones",
    "~/Library/Preferences/com.edijs.MacZones.plist",
  ]

  caveats <<~EOS
    MacZones needs Accessibility access to move windows:
      System Settings → Privacy & Security → Accessibility → enable MacZones
  EOS
end
