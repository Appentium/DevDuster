cask "devduster" do
  version "0.1.3"
  sha256 "1c482a83cb05792fcd145ca2692f14dcda237030504161c760b8ddf44da0cdab"

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
