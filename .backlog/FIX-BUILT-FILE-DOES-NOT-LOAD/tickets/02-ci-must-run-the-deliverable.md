# 02 — CI must run the built `CTLD.lua`, not just weigh it

**Status:** 🔄 in-progress

Ticket 01 fixes today's defect. This one fixes the reason a non-loading file could be tagged and
released.

## The gap

`CTLD.lua` is the only artefact this project ships, and it is the only artefact nothing executes:

- `lua-lint` runs `luac5.1 -p` over `src/` — syntax, per module, never the merged file.
- `busted` loads `src/` through `tests/ci/helpers/loader.lua`, which calls
  `CTLDConfig.get():load()` **first** and never loads `src/scenes/*.lua` — so the suite cannot
  reproduce the shipped ordering even in principle.
- `build` produces `CTLD.lua` and asserts `Test-Path` and `Length -ne 0`.

A file that raises on line 3 passes all three.

## What changes

A new `smoke` job in `.github/workflows/ci.yml`:

```yaml
  smoke:
    name: Built CTLD.lua Loads
    runs-on: ubuntu-latest
    needs: build
    steps:
      - uses: actions/checkout@v7
      - uses: actions/download-artifact@v7
        with: { name: CTLD }
      - name: Install Lua 5.1
        run: sudo apt-get update && sudo apt-get install -y lua5.1
      - name: Load the built CTLD.lua with DCS stubs
        run: lua5.1 tests/ci/smoke/load_built_ctld.lua CTLD.lua
```

and the runner it calls, `tests/ci/smoke/load_built_ctld.lua`:

1. `dofile("tests/ci/helpers/dcs_stubs.lua")` — the same stubs busted uses, so the two cannot
   drift apart.
2. Load and run `CTLD.lua` under `xpcall` with a `debug.traceback` handler.
3. Assert the chunk returned without raising **and** that it actually did its work — checking a
   post-`initialize()` observable, not the mere absence of an error, so a future `pcall` swallowing
   the failure internally cannot turn this green. Two observables, both already there, so nothing
   is added to the product for the sake of the test:
   - `CTLDConfig.get().isLoaded == true` — `ctld.initialize()` ran to the point of loading config.
   - `CTLDSceneManager.getInstance()` exposes the five built-in scene models — the exact thing
     today's bug destroys, asserted by count rather than by "no error".
4. Print the traceback and `os.exit(1)` on failure.

### What this does *not* cover, deliberately

`ci.yml` runs on `push`/`pull_request` for `develop` and `master`. It does **not** run on tags, and
`release.yml` (and `dev-build.yml`) rebuild `CTLD.lua` on `windows-latest` and publish it without
ever loading it. So the gate protects the branch, not the release.

That is enough to close *this* hole: the offending commit would have turned `develop` red and never
been merged, hence never tagged. But the second curtain is missing, and closing it is not a
one-liner — both workflows would have to be split (build → verify → publish) or grow a Lua 5.1
interpreter on a Windows runner. Left out on purpose rather than bolted on badly; raised for the
maintainer as a follow-up lot.

## Watch out

- **The stubs are shared on purpose.** Do not copy `dcs_stubs.lua` into `tests/ci/smoke/`: a
  private copy would rot, and the whole point is that the file loads against the same DCS surface
  the suite already maintains. If a global is missing, add it to the shared stubs.
- **The runner must not load `src/` modules.** It tests the *merged* artefact; touching
  `tests/ci/helpers/loader.lua` or `init.lua` would reintroduce the ordering that hides the bug.
  `dcs_stubs.lua` only, nothing else.
- **No `busted` here.** This job must survive `busted` being unavailable or red; it answers one
  question only, and its answer must be readable on its own.
- `needs: build` means the smoke job consumes the artefact the build job uploaded, not a rebuild —
  it must judge the bytes that ship.

## Acceptance

- The job is red against the current `develop` build (before ticket 01's fix) with the
  `CTLD configuration is not loaded` traceback visible in the step log. **Verify this**, do not
  assume it: a gate that has never failed has not been shown to work.
- The job is green once ticket 01 lands.
- Deliberately breaking the merged file (e.g. a stray `error()` at the top of a scene file) turns
  it red again.
- The job adds no dependency beyond `lua5.1` from apt.

## Tests

The job *is* the test. What needs proving is that it can fail — see Acceptance, which requires the
red run to be observed, both ways.
