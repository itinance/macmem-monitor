# macmem

A macOS CLI that shows where your memory is going:

- **Top apps** by combined footprint (helper/renderer processes collapsed into their app).
- **Swap** total plus the **measured** per-app compressed memory driving it (see below).
- **Browser tabs** (Safari / Brave / Chrome / Edge) with URLs and best-effort per-tab estimates.

> Per-tab memory is an **estimate** — macOS does not expose it directly. It is
> always labeled with confidence and left blank when ambiguous. The per-app swap
> contributors, by contrast, are **measured** compressed-memory values, not estimates.

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

## Install (from source)

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

# Distribution
just install            # build release + copy binary to {{prefix}}/bin (default /usr/local)
just prefix=~/.local install   # install to a custom prefix
just uninstall          # remove an installed binary
just bin-path           # print the resolved release binary path

# Meta
just ci                 # mirror CI: clean release build + full test suite
```

## License

MIT — see [LICENSE](LICENSE).
