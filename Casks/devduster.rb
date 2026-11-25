cask "devduster" do
  version "0.2.0"
  sha256 "49fb8b9747152bd062d90a3d72748d82c0547dd21249c093f275d395ab0c6256"

  url "https://github.com/Appentium/DevDuster/releases/download/v#{version}/DevDuster.zip"
  name "DevDuster"
  desc "Mac cleaner for developers"
  homepage "https://devduster.com"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "DevDuster.app"
  binary "#{appdir}/DevDuster.app/Contents/MacOS/duster"

  zap trash: [
    "~/Library/Application Support/DevDuster",
    "~/Library/LaunchAgents/com.appentium.devduster.schedule.plist",
    "~/Library/Logs/DevDuster",
    "~/Library/Preferences/com.appentium.devduster.plist",
  ]
end
