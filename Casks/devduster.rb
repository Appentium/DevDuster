cask "devduster" do
  version "0.1.2"
  sha256 "d9878b6dc9efaed33ddf3df3404b32baa1ff9466e1c43e49c41a4a46593306be"

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
