cask "devduster" do
  version "0.1.1"
  sha256 "08c70fe8f36c61044e613983074dfc93b4151fb2f3646172ee0d65d256bc0181"

  url "https://github.com/Appentium/DevDuster/releases/download/v#{version}/DevDuster.zip"
  name "DevDuster"
  desc "Mac cleaner for developers"
  homepage "https://devduster.com"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on arch: :arm64

  app "DevDuster.app"
  binary "#{appdir}/DevDuster.app/Contents/MacOS/duster"

  zap trash: [
    "~/Library/Application Support/DevDuster",
    "~/Library/LaunchAgents/com.appentium.devduster.schedule.plist",
    "~/Library/Logs/DevDuster",
    "~/Library/Preferences/com.appentium.devduster.plist",
  ]
end
