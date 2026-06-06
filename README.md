# macmem

A macOS CLI that shows where your memory is going:

- **Top apps** by combined footprint (helper/renderer processes collapsed into their app).
- **Swap** total plus a confidence-labeled estimate of likely contributors.
- **Browser tabs** (Safari / Brave / Chrome / Edge) with URLs and best-effort per-tab estimates.

> Per-tab memory and per-app swap are **estimates** — macOS does not expose them
> directly. They are always labeled with confidence and left blank when ambiguous.

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
sudo macmem                  # include root-owned processes
```

The first run prompts for **Automation** access per browser (needed to read tab URLs).
For full process coverage including system/root processes, run with `sudo`.

## License

MIT — see [LICENSE](LICENSE).
