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
make PID 31874  worker-multi-2  cwd ~/workspace/acme/acme-uitweaks/apps/backend
make PID 81626  run-api         cwd ~/workspace/acme/acme-hotfix/apps/backend
make PID 81627  worker-multi-2  cwd ~/workspace/acme/acme-hotfix/apps/backend
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
- Applies to **both** the TOP APPS section and the SWAP/compressed section, because
  both render `AppGroup`s produced by `AppGrouper`.

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
- `commandLine: String?` — the process arguments (everything after the executable
  path), read natively via `sysctl(KERN_PROCARGS2)`. Used for the `(target)` suffix
  (`run-api`, `worker-multi-2`). `nil` when unreadable. Leading/trailing whitespace
  trimmed; collapsed to `nil` if empty.

Both are populated in `NativeMemoryProvider`. `FakeMemoryProvider` lets tests supply
them directly. Failure to read either field is non-fatal — the process still appears,
just with less detail (honest degradation, consistent with the rest of the tool).

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

No structural renderer change. TOP APPS continues to append its `(N proc)` count after
the (now richer) `name`; the SWAP/compressed section prints the richer `name` as-is.
Existing alignment logic is preserved; longer labels simply occupy more width.

## Error Handling

- cwd unreadable → `nil` → bare-name collapse (decision 2). No crash, no sudo demand.
- args unreadable → `nil` → label omits the `(target)` suffix.
- Both readers wrap their syscalls and return `nil` on any non-success status.

## Testing

- `ProcessLabelTests` (new): `groupKey` for the three cases; `shortestUniqueSuffixes`
  for cohorts that collide at the tail (`.../apps/backend` × 2) and singletons;
  `displayLabel` for shortestUnique vs fullPath vs collapsed-nil-cwd.
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
