cask "aterm" do
  version "0.1.0"
  sha256 :no_check # Updated on release

  url "https://github.com/user/aTerm/releases/download/v#{version}/aTerm-#{version}.dmg"
  name "aTerm"
  desc "Native macOS terminal emulator with AI intelligence and model flexibility"
  homepage "https://github.com/user/aTerm"

  depends_on macos: ">= :ventura"

  app "aTerm.app"

  zap trash: [
    "~/Library/Application Support/aTerm",
    "~/Library/Caches/com.aterm.app",
    "~/Library/Preferences/com.aterm.app.plist",
  ]
end
