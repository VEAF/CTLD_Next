# FIX-BUILT-FILE-DOES-NOT-LOAD — `CTLD.lua` 2.0.0-rc8 aborts while loading

**Status:** 🔄 in-progress

Reported by **Tripack** on the VEAF Discord, 2026-09-12
([VEAF-Mission-Creation-Tools issue #957](https://github.com/VEAF/VEAF-Mission-Creation-Tools/issues/957)),
against VEAF Tools 6.22.0 — the first VEAF release to vendor `2.0.0-rc8`.

## The deviation

The released `CTLD.lua` does not load. Not "misbehaves once loaded": the main chunk raises, and
DCS abandons the file two thirds of the way through it.

Reproduced outside DCS, against the exact artefact VEAF vendors, under a real Lua 5.1 interpreter
with the repository's own DCS stubs. The traceback is identical, line for line, to the one in the
report:

```
CTLD.lua:172  (error)  →  5802 'log'  →  7810 '_init'  →  7799 'getInstance'  →  23078 main chunk
```

Read from the bottom:

1. **`CTLD.lua:23078`** — `scenes/CTLD_farpScene.lua` ends with
   `CTLDSceneManager.getInstance():registerSceneModel(farpScene)`. This is **main-chunk** code:
   it runs while the file is being loaded, long before `ctld.initialize()`. Four other scene files
   do the same; the first one to run is the one that raises.
2. **`CTLD_sceneManager.lua`, `CTLDSceneManager:_init`** — logs
   `"CTLDSceneManager: initialized (%d built-in scene(s))"`.
3. **`CTLD_utils.lua`, `ctld.utils.log`** — reads `ctld.gs("debugScreenLog")` unguarded, to decide
   whether to mirror the line on screen.
4. **`CTLD_config.lua:106`, `CTLDConfig:getSetting`** — refuses, by design, to serve a setting
   before `ctld.initialize()`. `error(..., 0)`.

## Why it is new, and why nothing caught it

Every piece above is old except step 4. `FIX-CONFIG-NOT-LOADED-GUARD` (PR #141, merged
2026-08-26 22:47) turned a silent `nil` into a hard `error()` — deliberately, and for good
reasons that still hold. Before it, `ctld.gs("debugScreenLog")` returned `nil` during the main
chunk, `nil == true` was false, and the screen-log branch was simply skipped. Nobody noticed the
read was illegal because nothing punished it.

`2.0.0-rc8` was tagged **34 minutes later**. Three gates were in place and none of them looks at
this:

- **`lua-lint`** syntax-checks `src/` with `luac5.1 -p`. Syntax is not execution.
- **`busted`** loads `src/` modules through `tests/ci/helpers/loader.lua`, which (a) calls
  `CTLDConfig.get():load()` **before** loading the managers, and (b) does not load
  `src/scenes/*.lua` at all. The suite therefore never reproduces the one ordering that ships —
  scenes self-registering against an unloaded config.
- **`build` (Merge Build)** produces `CTLD.lua` and asserts it *exists and is non-empty*. It never
  runs it.

So the deliverable is the only artefact nothing executes, and the failure lives exactly there.

## What the integrator sees

Worse than a broken CTLD. VEAF Tools emits every script of its loading trigger as one concatenated
Lua chunk (`a_do_script_file(k1);a_do_script_file(k2);…`), and CTLD sits third, ahead of the VEAF
framework. The raise kills the rest of the chunk, so the VEAF scripts never load either: the
mission boots, is playable, and has **no F10 radio menu at all** — neither CTLD's nor VEAF's. The
only clue is one `Mission script error` line naming CTLD.

Any mission built with VEAF Tools 6.22.0 with CTLD enabled is affected, and CTLD is enabled by
default there.

## The fix

Two changes, one behavioural and one structural.

1. **`ctld.utils.log` must be safe at any point in the lifecycle.** Logging is infrastructure: it
   is called *from* initialization code, so it cannot require initialization to have finished.
   Guard the screen-log read the way `CTLD_i18n.lua`'s `_activeLang()`
   ([:71](../../src/CTLD_i18n.lua#L71)) already guards its own very-early `ctld.gs("i18n_lang")`
   read — `pcall`, fall through when it fails. Same problem, same shape, and that precedent was
   already reviewed and accepted in PR #141.

   The `getSetting` guard itself is **not** relaxed. It is doing its job; the logger was simply an
   illegal caller.

2. **Execute the deliverable in CI.** A new job loads the built `CTLD.lua` under Lua 5.1 with
   `tests/ci/helpers/dcs_stubs.lua` and fails if the main chunk raises. This is the gate whose
   absence let a non-loading file get tagged, and it is the part of this lot that has value beyond
   today's bug.

## Definition of done

- The built `CTLD.lua` loads under Lua 5.1 with the repository's DCS stubs, with no config loaded
  beforehand, and reaches `ctld.initialize()` on its own.
- `ctld.utils.log(...)` called before `ctld.initialize()` writes to `env.info` and does not raise.
- The screen-log behaviour after initialization is unchanged: `debugScreenLog: true` still mirrors
  every line through `trigger.action.outText` with `debugScreenLogDuration`.
- A busted spec reproduces the shipped ordering — scene self-registration against an unloaded
  config — and fails without the fix.
- A CI job runs the built artefact and fails when it raises.
- `busted tests/ci/` green, `luacheck --config .luacheckrc src/` clean.
- `CHANGELOG.md` **Fixed** entry.
- Released as `2.0.0-rc9`: rc8 is unusable and must not stay the newest tag.

## Out of scope

- Relaxing or removing the `CTLDConfig:getSetting` guard. It found a real defect; that is the
  point of it.
- Making scene registration lazy, or moving it out of the main chunk. It is a legitimate pattern —
  external scene files (`CTLD_mineFieldScene.lua` and any third-party plugin) self-register at load
  time on purpose, which is documented in `CTLDSceneManager:registerSceneModel`. Changing it would
  break plugins to work around a logger bug.
- An audit of every other pre-init `ctld.gs` call site. The new CI job covers the load path
  wholesale, which is stronger than an enumeration — but see ticket 01's sweep, which records what
  the fix was checked against.
- Closing the same gap in `release.yml` and `dev-build.yml`. Both rebuild `CTLD.lua` on a Windows
  runner and publish it without loading it, and `ci.yml` does not run on tags — so the new gate
  protects the branch, not the release. That is enough for this defect (a red `develop` means no
  merge, hence no tag), but the second curtain is genuinely missing. It needs either splitting
  those workflows into build → verify → publish, or a Lua 5.1 interpreter on `windows-latest`;
  either is its own lot, and neither should be improvised inside a hotfix. Flagged for the
  maintainer, see ticket 02.

## Further Notes

- No ADR. The behavioural change is one `pcall` aligned on an existing, documented precedent in
  the same codebase; the CI job is a missing gate, not a new mechanism.
- Direct lineage: this lot exists *because* `FIX-CONFIG-NOT-LOADED-GUARD` did its job. That lot's
  own "Watch out" section explicitly checked `CTLD_i18n.lua`'s pre-init tolerance and found it
  compatible. It checked the one pre-init caller it knew about; `ctld.utils.log` is the one it did
  not. Enumerating known callers is what missed this — hence the wholesale gate above.
