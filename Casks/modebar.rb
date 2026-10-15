cask "modebar" do
  version "0.1.0"
  # Fill sha256 from `./scripts/package.sh #{version}` after the first GitHub Release.
  sha256 "REPLACE_WITH_SHA256_FROM_scripts_package_sh"

  url "https://github.com/safakkizkin/modebar/releases/download/v#{version}/ModeBar-#{version}.zip"
  name "ModeBar"
  desc "Menu bar controller for QuietComfort-class headphones (BMAP over RFCOMM)"
  homepage "https://github.com/safakkizkin/modebar"

  depends_on macos: ">= :sonoma"

  app "ModeBar.app"

  zap trash: [
    "~/Library/Preferences/app.modebar.macos.plist",
  ]

  caveats <<~EOS
    ModeBar talks to headphones over Classic Bluetooth RFCOMM and is not
    sandboxed. Gatekeeper may quarantine unsigned builds; if macOS blocks
    launch after install:

      xattr -dr com.apple.quarantine /Applications/ModeBar.app

    Pair headphones in System Settings first. Supported today: QuietComfort
    Headphones (prince / product 0x4075) and other BMAP RFCOMM models that
    answer on channels 8, 2, or 9 — not all Bose products.
  EOS
end
