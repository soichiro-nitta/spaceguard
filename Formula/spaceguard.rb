class Spaceguard < Formula
  desc "Keep Codex and desktop automation scoped to the current macOS Space"
  homepage "https://github.com/soichiro-nitta/spaceguard"
  head "https://github.com/soichiro-nitta/spaceguard.git", branch: "main"

  depends_on :macos

  def install
    system "/usr/bin/swiftc",
      "SpaceGuard.swift",
      "-o",
      "spaceguard",
      "-framework",
      "AppKit",
      "-framework",
      "CoreGraphics"
    bin.install "spaceguard"
  end

  test do
    assert_match "usage: spaceguard", shell_output("#{bin}/spaceguard --help")
  end
end
