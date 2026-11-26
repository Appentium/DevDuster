cask "devduster" do
  version "0.3.0"
  sha256 "dbab4684d58fe24d6b6cf5310b691ab663323cc20f1da81916422fdf8e1fd0fa"

  url "https://github.com/Appentium/DevDuster/releases/download/v#{version}/DevDuster-macos.zip"
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
