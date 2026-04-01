cask "aterm" do
  version "0.1.0"
  sha256 :no_check # Updated on release

  # Set to the GitHub user or org that publishes release DMGs (no secrets in this file).
  url "https://github.com/YOUR_GITHUB_USER/aTerm/releases/download/v#{version}/aTerm-#{version}.dmg"
  name "aTerm"
  desc "Native macOS terminal emulator with AI intelligence and model flexibility"
  homepage "https://github.com/YOUR_GITHUB_USER/aTerm"

  depends_on macos: ">= :ventura"

  app "aTerm.app"

  zap trash: [
    "~/Library/Application Support/aTerm",
    "~/Library/Caches/com.aterm.app",
    "~/Library/Preferences/com.aterm.app.plist",
  ]
end
