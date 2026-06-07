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
sudo macmem                  # include root-owned processes
```

The first run prompts for **Automation** access per browser (needed to read tab URLs).
For full process coverage including system/root processes, run with `sudo`.

## License

MIT — see [LICENSE](LICENSE).
