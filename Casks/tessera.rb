# Homebrew cask for Tessera. Submit to a tap (e.g. homebrew-tessera) or, once the
# project has traction, to homebrew/cask. Update `version` + `sha256` per release
# (the release script prints the sha256).
cask "tessera" do
  version "1.0.0"
  sha256 "b7f3d273cff114d99ccf4b0ae0619aec4d0ccac069323c1e4ea01f0d71b53e64" # ← from ./scripts/release.sh output

  url "https://github.com/IvanKuria/tessera/releases/download/v#{version}/Tessera-#{version}.dmg",
      verified: "github.com/IvanKuria/tessera/"
  name "Tessera"
  desc "Unofficial native macOS app for the Kalshi prediction market"
  homepage "https://github.com/IvanKuria/tessera"

  depends_on macos: ">= :sonoma" # macOS 14+

  app "Tessera.app"

  zap trash: [
    "~/Library/Application Support/Tessera",
    "~/Library/Group Containers/group.app.tessera",
    "~/Library/Preferences/app.tessera.Tessera.plist",
  ]
end
