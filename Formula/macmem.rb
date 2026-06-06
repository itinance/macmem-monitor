class Macmem < Formula
  desc "macOS CLI: heaviest apps, swap usage, and browser tabs"
  homepage "https://github.com/itinance/macmem-monitor"
  url "https://github.com/itinance/macmem-monitor/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "72988ac4aaa30bcceb6e6ff6095306e8c204dcb7e273145395a9e1e890ad3683"
  license "MIT"

  depends_on xcode: ["15.0", :build]
  depends_on :macos

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin.install ".build/release/macmem"
  end

  test do
    assert_match "TOP APPS", shell_output("#{bin}/macmem --no-tabs --no-swap")
  end
end
