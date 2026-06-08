# macmem

A macOS CLI that shows where your memory is going:

- **Top apps** by combined footprint (helper/renderer processes collapsed into their app).
- **Swap** total plus the **measured** per-app compressed memory driving it (see below).
- **Browser tabs** (Safari / Brave / Chrome / Edge): each browser's **measured** total
  footprint and process count, with its open tab URLs listed underneath.

> Per-**tab** memory is not shown — no macOS or browser automation API exposes it.
> Instead the section reports each browser's **measured** total footprint (the same
> figure as TOP APPS) and lists its tabs. Safari's WebKit content is system-shared
> and only attributable with `--responsible-pid`; until then Safari's total is shown
> as unavailable rather than guessed. The per-app swap contributors are likewise
> **measured** compressed-memory values, never estimates.

## Understanding compressed memory (CMPRS)

The SWAP section lists per-app **compressed memory** (labeled `[measured]`), read
from `top`'s `CMPRS` column. It's worth understanding exactly what this is so you
read it correctly:

- **It is not the app's total memory.** It's only the portion macOS has *compressed*.
  An app's full footprint (shown in the TOP APPS section) is larger — e.g. a browser
  might show 59 GB total of which 36 GB is compressed.
- **macOS compresses before it swaps.** When memory gets tight, the system squeezes
  a process's cold/inactive pages in RAM (the *memory compressor*) instead of writing
  them to disk immediately. Compressed memory therefore mostly lives in RAM (just
  smaller); only under further pressure does some of it spill to the on-disk swapfile.
- **There is no per-process on-disk-swap counter on macOS** — no public or stable API
  reports how many bytes of a given app sit in the swapfile. The `Used … / …` swap
  total is *system-wide* and cannot be broken down per app. Compressed memory is the
  closest honest per-app proxy for "who is driving swap pressure."

**How to read it:** a high `CMPRS` value means the app is holding a large pile of cold
memory the system has had to compress to cope. Those are your swap-pressure culprits —
quitting the top one or two (and optionally running `sudo purge`) is usually what
brings swap back down.

This data is read without `sudo` (`top` is entitled to report it for all processes).
If `top` cannot be read at all, the section says *"unavailable (could not read from
top)"* rather than silently showing nothing.

## Install

### Homebrew (recommended)

```bash
brew install itinance/tap/macmem
```

Or tap first, then install by short name:

```bash
brew tap itinance/tap
brew install macmem
```

Upgrade later with `brew upgrade macmem`. The formula builds from source, so a recent
Xcode (15+) toolchain is required at install time.

### From source

```bash
swift build -c release
cp .build/release/macmem /usr/local/bin/
```

## Usage

```bash
macmem                       # full snapshot
macmem --json                # machine-readable
macmem --top 5               # 5 per section
macmem --no-tabs             # skip browser tabs
macmem --no-swap             # skip the swap section
macmem --watch 2             # refresh every 2s
macmem --responsible-pid     # use private API for better process→app grouping (off by default; may carry notarization considerations)
macmem --browser "Safari"    # only query tabs from a single browser (Brave Browser, Google Chrome, Microsoft Edge, or Safari)
macmem --full-paths          # show full working-directory paths in CLI process labels (default: shortest unique suffix)
sudo macmem                  # include root-owned processes
```

The first run prompts for **Automation** access per browser (needed to read tab URLs).
For full process coverage including system/root processes, run with `sudo`.

## Development

A [`just`](https://github.com/casey/just) task runner wraps the common workflows.
Run `just` with no arguments to list every recipe.

```bash
# Build & test
just build              # debug build
just release            # optimized release build
just test               # full XCTest suite
just test-summary       # run tests, print only the pass/fail line
just test-one <filter>  # run a single test/case, e.g. just test-one AppGrouper
just clean              # remove build artifacts

# Run (extra args forward to the CLI)
just run --top 5 --no-tabs   # run macmem with flags
just help                    # macmem --help
just json                    # full snapshot as JSON
just top                     # quick glance: top 5 apps, no tabs/swap
just watch 1                 # live-refreshing view, 1s interval
just sudo-run                # release build, run under sudo (full process coverage)

# MenuBar app (LSUIElement menubar agent)
just app                # assemble .build/MacMem.app from the release build
just run-app            # build the bundle and launch it

# Distribution
just install            # build release + copy binary to {{prefix}}/bin (default /usr/local)
just prefix=~/.local install   # install to a custom prefix
just uninstall          # remove an installed binary
just bin-path           # print the resolved release binary path

# Meta
just ci                 # mirror CI: clean release build + full test suite
```

## Releasing the menubar app

The menubar app (`MacMem.app`) ships as a Homebrew cask
(`brew install --cask itinance/tap/macmem-monitor`). `just app` produces an
*ad-hoc* signed bundle for local use; release builds must be **Developer
ID-signed and notarized** so users don't hit Gatekeeper.

**One-time setup:**

1. Create a **Developer ID Application** certificate (Xcode → Settings →
   Accounts → your team → Manage Certificates → `+` → *Developer ID
   Application*). This is distinct from "Apple Development"/"Apple Distribution"
   certs — only Developer ID can notarize a direct download. For an
   organization account, the **Account Holder** must create it.
2. Store a notarytool credential as a keychain profile (using an
   [app-specific password](https://support.apple.com/102654) or an App Store
   Connect API key):

   ```bash
   xcrun notarytool store-credentials "macmem-notary" \
     --apple-id you@example.com --team-id 87HR586LH8 --password <app-specific-pw>
   ```

**Cutting a release:**

```bash
just release-app          # signs (hardened runtime), notarizes, staples; prints sha256
```

Then attach `.build/MacMem.app.zip` to a GitHub Release tagged `app-vX.Y.Z` and
update `version` + `sha256` in the tap's `Casks/macmem-monitor.rb`. A notarized
build means the cask no longer needs the `xattr` quarantine caveat.

## License

MIT — see [LICENSE](LICENSE).
