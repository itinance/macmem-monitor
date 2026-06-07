# Directory-Aware Labels for CLI Process Groups — Design

**Date:** 2026-06-07
**Status:** Approved decisions, pending spec review
**Component:** `MacMemCore` (`AppGrouper`, `ProcessSample`, providers, renderers, CLI)

## Problem

macmem groups bundle-less processes (CLI tools like `make`, `node`, `python`) purely
by their bare process name (`AppGrouper.swift` keys on `owner.name`). Every `make`
across every project therefore collapses into a single `make` line in both the TOP
APPS and SWAP/compressed sections. On a real machine this merges unrelated work:

```
make PID 31874  worker-multi-2  cwd ~/workspace/nestfainder/nestfainder-uitweaks/apps/backend
make PID 81626  run-api         cwd ~/workspace/nestfainder/nestfainder-hotfix/apps/backend
make PID 81627  worker-multi-2  cwd ~/workspace/nestfainder/nestfainder-hotfix/apps/backend
```

All three render as one `make` row, so the user cannot tell which project/target is
heavy, and the row's total swings with build activity. The same applies to `node`,
`python`, etc. The fix: give bundle-less CLI groups a directory- and argument-aware
identity and label.

## Scope

- **In scope:** processes **without** a bundle ID (CLI tools). The new identity and
  label logic applies to them only.
- **Out of scope / unchanged:** processes **with** a bundle ID (Brave, Code, Safari,
  etc.) and the responsible-PID grouping path. They already group correctly and keep
  their current names.
- Applies to **both** the TOP APPS section and the SWAP/compressed section. TOP APPS
  renders `AppGroup` directly. The SWAP section renders `CompressedMemoryEntry`
  (`Models.swift`), but the label still propagates: `CompressedMemoryAggregator.entries`
  copies `group.name` into `entry.appName` from the already-labeled `topApps`. There is
  therefore a **single labeling site** (`AppGrouper`); the aggregator inherits it.
  Because the aggregator re-ranks and re-cuts `topApps` to its own `topN`, the
  shortest-unique-suffix computation must run over the full bundle-less cohort *before*
  any `topN` truncation (see Identity & Label Logic) so suffixes are stable in both
  sections.

## Decisions (from brainstorming)

1. **Split by directory.** A bundle-less group's identity is `(name, workingDirectory)`.
   Each project's `make` becomes its own row. Same name + same cwd (e.g. a `make -j`
   build tree) stays merged into one row.
2. **cwd-unreadable fallback = bare name.** When the working directory cannot be read
   (e.g. a root-owned process under a non-sudo run), those processes collapse into a
   single bare-name row labeled `make  (N processes, dir unavailable)`.
3. **Directory display = shortest unique suffix** (default). Per same-name cohort,
   show the fewest trailing path components that keep every shown row distinct
   (minimum 1 component).
4. **`--full-paths` flag.** When set, the directory is shown as the full
   `$HOME`-abbreviated path (`~/...`) instead of the shortest unique suffix.

## Data Captured

`ProcessSample` gains two best-effort optional fields (both default `nil`):

- `workingDirectory: String?` — absolute cwd of the process. Read natively via
  `proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, ...)`. Readable for processes owned by the
  current user; `nil` for other users' processes without sudo, and `nil` on any error.
- `commandLine: String?` — the **full** process arguments (everything after the
  executable path, joined with spaces), read natively via `sysctl(KERN_PROCARGS2)`.
  This is raw argv: for `make -j8 run-api` it is `-j8 run-api`, so the label suffix is
  `(-j8 run-api)`, **not** a cleaned `(run-api)`. We deliberately do not try to guess
  the "target" — flag-stripping is fragile and project-specific. Whitespace-trimmed;
  `nil` when unreadable or empty. Note the synergy with middle-truncation (see Renderer
  Impact): when a label is too long, the trailing token — usually the most telling part,
  e.g. the make target — is preserved.

Both are populated in `NativeMemoryProvider`. `FakeMemoryProvider` lets tests supply
them directly. Failure to read either field is non-fatal — the process still appears,
just with less detail (honest degradation, consistent with the rest of the tool).

**Source compatibility:** `ProcessSample.init` is a public memberwise initializer with
no defaults (`Models.swift:23`), called twice in `NativeMemoryProvider` and across many
tests. The two new parameters **must be declared with `= nil` defaults** so every
existing call site compiles unchanged; only `NativeMemoryProvider` passes real values.

**macOS 26 import friction (implementation note, not a spec change):**
`NativeMemoryProvider.swift:79-82` already documents that `PROC_PIDPATHINFO_MAXSIZE` is
not importable by the Swift overlay on macOS 26 and uses a hardcoded workaround. Expect
the same friction for `PROC_PIDVNODEPATHINFO` / `proc_pidinfo` buffer sizing and for
`KERN_PROCARGS2`; the implementer should budget for hardcoding the relevant constants or
sizing buffers manually, following the existing pattern in that file.

## Identity & Label Logic

A new small helper `ProcessLabel` holds the pure string logic (no I/O), so it is unit
testable in isolation and `AppGrouper` stays an orchestrator:

- `groupKey(name:bundleID:workingDirectory:) -> String`
  - bundle ID present → existing behavior (base bundle ID).
  - bundle-less + cwd present → `"\(name)\u{0}\(cwd)"`.
  - bundle-less + cwd nil → `name` (collapses all unreadable same-name processes).
- `shortestUniqueSuffixes(paths:) -> [String: String]`
  - Input: the set of distinct cwds within one same-name cohort.
  - Output: per cwd, the shortest trailing path-component suffix (min 1 component)
    that is unique across the cohort. A singleton cohort yields its last component.
  - **Tiebreak:** if two distinct cwds share their entire shorter tail (one path's
    components are a suffix of the other's, e.g. `/a/b/c` vs `/b/c`), no trailing
    suffix can separate them. In that case both colliding entries fall back to their
    full `$HOME`-abbreviated (`~/…`) path, guaranteeing the rendered rows are distinct.
- `displayLabel(name:workingDirectory:commandLine:style:processCount:) -> String`
  - cwd present: `"\(name) — \(dir)\(target)"` where `dir` is the shortest-unique
    suffix (`style == .shortestUnique`) or the `~`-abbreviated full path
    (`style == .fullPath`), and `target` is `" (\(commandLine))"` when `commandLine`
    is non-nil else `""`.
  - cwd nil (collapsed group): `"\(name)  (\(processCount) process(es), dir unavailable)"`.

`AppGrouper.group(...)` flow:
1. Resolve each sample's owner (existing logic), now also carrying `workingDirectory`
   and `commandLine` through for bundle-less owners.
2. Accumulate into groups keyed by `ProcessLabel.groupKey`.
3. After accumulation, for bundle-less groups, compute shortest-unique suffixes per
   same-name cohort and assign each group's display `name` via
   `ProcessLabel.displayLabel`. Bundle-ID groups keep their current name.
4. Sort by footprint and take `topN` as today.

`AppGroup` carries the final display string in `name` (renderers already print
`name`), plus the existing `processCount`/`pids`. The shortest-suffix computation runs
over all bundle-less groups before the `topN` cut so suffixes are stable regardless of
truncation.

## CLI

`main.swift` gains a `--full-paths` boolean flag (default off). It threads through
`SnapshotBuilder` into `AppGrouper.group(..., pathStyle:)` as
`PathStyle.shortestUnique` (default) or `.fullPath`. Documented in README usage and
exposed as a `just` recipe note if natural. The flag affects only the directory
portion of bundle-less labels; it does not change grouping/identity.

## Renderer Impact

**TOP APPS truncation must change — this is required, not cosmetic.** Today
`TextRenderer.nameColumn` (`TextRenderer.swift:14-21`) hard-truncates to
`nameWidth = 30` via `prefix(width-1) + "…"`. That cuts the **tail** of the label —
exactly the `(target)` and the deepest, most-disambiguating path components the feature
adds. A label like `make — apps/backend (worker-multi-2)` would render as
`make — apps/backend (worker-m…`, defeating the feature in the very section the Problem
statement illustrates. The SWAP/compressed section already prints `appName` untruncated
(`TextRenderer.swift:53-54`), so only TOP APPS needs fixing. Required changes:

- **Auto-size the name column** to the longest label among the shown TOP APPS rows,
  capped at a constant `nameWidthMax` (60). Rows pad to that width for alignment;
  truncation happens only beyond the cap.
- **Middle-truncate** when a label exceeds the cap: preserve the head and the trailing
  token, e.g. `make — …/nestfainder-hotfix/apps/backend (worker-multi-2)`. This keeps
  both the process name and the trailing argv token (the make target) visible, and
  composes with the raw-argv decision above.
- The `(N proc)` count still follows the name as today; the SWAP section is unchanged.

`nameColumn`'s signature gains the computed width; a new `middleTruncate(_:width:)`
helper holds the ellipsis-in-the-middle logic and is unit-tested directly.

## Error Handling

- cwd unreadable → `nil` → bare-name collapse (decision 2). No crash, no sudo demand.
- args unreadable → `nil` → label omits the `(target)` suffix.
- Both readers wrap their syscalls and return `nil` on any non-success status.

## Testing

- `ProcessLabelTests` (new): `groupKey` for the three cases; `shortestUniqueSuffixes`
  for cohorts that collide at the tail (`.../apps/backend` × 2) and singletons, **plus
  the suffix-of-suffix tiebreak** (`/a/b/c` vs `/b/c` → both fall back to full `~`-path);
  `displayLabel` for shortestUnique vs fullPath vs collapsed-nil-cwd; raw-argv suffix
  (`-j8 run-api` renders verbatim, not cleaned).
- `RendererTests` (extend): `middleTruncate` preserves head and trailing token; a
  TOP APPS label over `nameWidthMax` is middle-truncated (trailing argv token survives);
  the name column auto-sizes to the longest shown label up to the cap.
- `AppGrouperTests` (extend): same name + different cwd → separate groups; same name +
  same cwd → merged; bundle-less + nil cwd → single collapsed bare-name group;
  bundle-ID groups unaffected; `pathStyle: .fullPath` produces `~`-abbreviated labels.
- `SnapshotBuilderTests` (extend): `--full-paths`/`pathStyle` threads through; default
  is `.shortestUnique`.
- Native readers: a smoke test that `workingDirectory`/`commandLine` are non-nil for
  the test process's own PID (skipped gracefully if the platform denies it).

## Non-Goals

- No per-process on-disk swap attribution (still impossible on macOS — see the CMPRS
  README section).
- No change to bundle-ID app grouping or responsible-PID handling.
- No sudo requirement; unreadable data degrades to less-specific labels.
