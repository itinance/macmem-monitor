# macmem — task runner (https://github.com/casey/just)
# Run `just` with no args to list recipes.

# Where `just install` puts the binary. Override: `just prefix=~/.local install`
prefix := "/usr/local"

# Default recipe: show the list.
default:
    @just --list

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

# Debug build of the whole package.
build:
    swift build

# Optimized release build.
release:
    swift build -c release

# Remove build artifacts.
clean:
    swift package clean
    rm -rf .build

# ---------------------------------------------------------------------------
# Test
# ---------------------------------------------------------------------------

# Run the full XCTest suite.
test:
    swift test

# Run tests and print just the pass/fail summary line.
test-summary:
    @swift test 2>&1 | grep -E "Executed|error:" | tail -1

# Run a single test or test case by name filter, e.g. `just test-one AppGrouper`.
test-one filter:
    swift test --filter {{filter}}

# ---------------------------------------------------------------------------
# Run (debug build; pass any macmem flags through, e.g. `just run --json`)
# ---------------------------------------------------------------------------

# Run macmem. Extra args forward to the CLI: `just run --top 5 --no-tabs`.
run *args:
    swift run macmem {{args}}

# Show macmem's own --help.
help:
    swift run macmem --help

# Full snapshot as pretty JSON.
json:
    swift run macmem --json

# Top 5 apps only, no tabs, no swap — quick glance.
top:
    swift run macmem --top 5 --no-tabs --no-swap

# Live-refreshing view (Ctrl-C to stop). Optional interval seconds: `just watch 1`.
watch interval="2":
    swift run macmem --watch {{interval}}

# Run with sudo for full process coverage (reads root-owned processes).
# You'll be prompted for your password.
sudo-run *args:
    swift build -c release
    sudo .build/release/macmem {{args}}

# ---------------------------------------------------------------------------
# Distribution
# ---------------------------------------------------------------------------

# Build release and copy the binary to {{prefix}}/bin (may need sudo for /usr/local).
install: release
    install -d "{{prefix}}/bin"
    install -m 0755 .build/release/macmem "{{prefix}}/bin/macmem"
    @echo "Installed -> {{prefix}}/bin/macmem"

# Remove an installed binary.
uninstall:
    rm -f "{{prefix}}/bin/macmem"
    @echo "Removed {{prefix}}/bin/macmem"

# ---------------------------------------------------------------------------
# Meta
# ---------------------------------------------------------------------------

# Mirror CI: clean release build + full test suite.
ci: release test

# Print the resolved release binary path.
bin-path:
    @echo "$(swift build -c release --show-bin-path)/macmem"

# ---------------------------------------------------------------------------
# MenuBar app bundle
# ---------------------------------------------------------------------------

# Assemble MacMem.app from the release build (LSUIElement menubar agent).
app:
    swift build -c release --product MacMemMenuBar
    rm -rf .build/MacMem.app
    mkdir -p .build/MacMem.app/Contents/MacOS
    cp Resources/MenuBar/Info.plist.template .build/MacMem.app/Contents/Info.plist
    cp .build/release/MacMemMenuBar .build/MacMem.app/Contents/MacOS/MacMemMenuBar
    codesign --force --sign - .build/MacMem.app
    @echo "Built .build/MacMem.app"

# Build the bundle and launch it.
run-app: app
    open .build/MacMem.app

# ---------------------------------------------------------------------------
# Signed + notarized release of the MenuBar app (for the Homebrew cask)
# ---------------------------------------------------------------------------
# Requires a one-time setup (see README "Releasing the menubar app"):
#   1. A "Developer ID Application" certificate in your login keychain.
#   2. A notarytool credential stored as a keychain profile, e.g.:
#        xcrun notarytool store-credentials "{{notary_profile}}" \
#          --apple-id you@example.com --team-id 87HR586LH8 --password <app-specific-pw>

# Developer ID identity used to sign release builds. Override on the CLI if needed.
signing_id := "Developer ID Application: ITinance GmbH (87HR586LH8)"
# notarytool keychain profile name created via `xcrun notarytool store-credentials`.
notary_profile := "macmem-notary"

# Developer ID-sign (hardened runtime) + notarize + staple MacMem.app -> .build/MacMem.app.zip (+sha256).
release-app:
    swift build -c release --product MacMemMenuBar
    rm -rf .build/MacMem.app
    mkdir -p .build/MacMem.app/Contents/MacOS
    cp Resources/MenuBar/Info.plist.template .build/MacMem.app/Contents/Info.plist
    cp .build/release/MacMemMenuBar .build/MacMem.app/Contents/MacOS/MacMemMenuBar
    codesign --force --options runtime --timestamp \
        --entitlements Resources/MenuBar/MacMem.entitlements \
        --sign "{{signing_id}}" .build/MacMem.app
    codesign --verify --strict --verbose=2 .build/MacMem.app
    rm -f .build/MacMem.app.zip
    ditto -c -k --keepParent .build/MacMem.app .build/MacMem.app.zip
    xcrun notarytool submit .build/MacMem.app.zip --keychain-profile "{{notary_profile}}" --wait
    xcrun stapler staple .build/MacMem.app
    rm -f .build/MacMem.app.zip
    ditto -c -k --keepParent .build/MacMem.app .build/MacMem.app.zip
    @echo "Notarized + stapled -> .build/MacMem.app.zip"
    @shasum -a 256 .build/MacMem.app.zip
