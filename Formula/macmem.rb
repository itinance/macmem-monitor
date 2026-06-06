class Macmem < Formula
  desc "macOS CLI: heaviest apps, swap usage, and browser tabs"
  homepage "https://github.com/itinance/macmem-monitor"
  url "https://github.com/itinance/macmem-monitor/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_RELEASE_TARBALL_SHA256" # TODO: fill at first tagged release
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
