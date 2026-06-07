class Macmem < Formula
  desc "macOS CLI: heaviest apps, swap usage, and browser tabs"
  homepage "https://github.com/itinance/macmem-monitor"
  url "https://github.com/itinance/macmem-monitor/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "1c7821c76444df02df1316379f1f1ed1c15268f6456a8c0d3c757f563a6beb3a"
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
