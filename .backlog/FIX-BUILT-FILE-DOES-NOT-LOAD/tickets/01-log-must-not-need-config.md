# 01 — `ctld.utils.log` must not require a loaded config

**Status:** 🔄 in-progress

See the PRD for the full traceback and why rc8 cannot load at all.

## What changes

1. `src/CTLD_utils.lua`, `ctld.utils.log` (~line 1907): the screen-log branch reads
   `ctld.gs("debugScreenLog")` unguarded. Guard it exactly as `CTLD_i18n.lua:71` guards its own
   very-early read:

   ```lua
   local okScreenLog, screenLog = pcall(ctld.gs, "debugScreenLog")
   if okScreenLog and screenLog == true then
       local duration = ctld.gs("debugScreenLogDuration")
       trigger.action.outText(msg, duration)
   end
   ```

   The inner `ctld.gs("debugScreenLogDuration")` needs no guard of its own: it is only reached once
   the first read has succeeded, which proves the config is loaded.

2. `CHANGELOG.md` `[Unreleased]`: a **Fixed** entry.

## Watch out

- **Do not touch `CTLDConfig:getSetting`.** Its refusal is correct and deliberate
  (`FIX-CONFIG-NOT-LOADED-GUARD`). The logger was an illegal caller; the guard is not the bug.
- **Do not touch the scene files or `registerSceneModel`.** Load-time self-registration is the
  documented extension point for external scene files and third-party plugins.
- `pcall(ctld.gs, key)` and not `pcall(function() return ctld.gs(key) end)`: `ctld.gs` is a plain
  global function by the time `log` runs, and the direct form allocates no closure per log line.
  (`_activeLang()` uses the closure form because it must also tolerate `ctld.gs` being *absent*.)
- Keep `env.info` and the file-log write **before** the guarded branch, untouched: a pre-init log
  line must still reach `dcs.log`. That is the only place the diagnosis can appear.

## Acceptance

- `ctld.utils.log("INFO", "x")` on a never-`:load()`-ed config does not raise, and `env.info`
  still receives `[CTLD][INFO] x`.
- With the config loaded and `debugScreenLog = true`, `trigger.action.outText` is still called
  once per log line, with `debugScreenLogDuration` as its second argument.
- With the config loaded and `debugScreenLog = false`, `trigger.action.outText` is not called.
- `CTLDSceneManager.getInstance()` on a never-`:load()`-ed config returns a manager and does not
  raise — the shipped ordering.
- `busted tests/ci/` green, `luacheck --config .luacheckrc src/` clean, `CTLD.lua` rebuilt.

## Tests

New `tests/ci/unit/log_pre_init_spec.lua` (the existing `utils_spec.lua` runs under the shared
helper, which loads a config on purpose — a spec about the *unloaded* state needs its own file and
its own reset).

Mirror `config_spec.lua`'s seam: `CTLDConfig._instance = nil; CTLDConfig.get()` **without**
`:load()`, restoring the previous instance in `after_each` so the rest of the suite is unaffected.

Cases:

- `ctld.utils.log("INFO", "hello")` does not raise, and the message reached `env.info`.
- `CTLDSceneManager.getInstance()` does not raise (the reported call path, one level up).
- After `:load()`, `debugScreenLog = true` ⇒ `trigger.action.outText` called with the message and
  `debugScreenLogDuration`; `debugScreenLog = false` ⇒ not called. Proves the `pcall` did not
  silently disable the feature it guards.

## Sweep — other pre-init `ctld.gs` readers

Recorded here rather than in a comment, so the next reader knows what was checked, not just what
was fixed. **Measured, not enumerated by eye**: the guard was neutralised at runtime (return `nil`
instead of raising) and every read taken while `isLoaded` was false was recorded with its
traceback, over a full load of the released `CTLD.lua`. Result: **19 pre-init reads, from exactly
three call sites**, and the file then reached `ctld.initialize()` and returned `LOADED OK` — which
also proves this branch is the *only* thing standing between rc8 and a clean load.

| Site | Key(s) read pre-init | State |
|---|---|---|
| `CTLD_utils.lua` `log` | `debugScreenLog` | **fixed here** |
| `CTLD_utils.lua` `reopenLogAppend` | `debug` (returns early, so `ctldLogPath` is never reached) | already safe — its sole caller wraps it in `pcall` |
| `CTLD_i18n.lua` `_activeLang` | `i18n_lang` | already safe — own `pcall` |

No manager `init()` appears: `CTLD_core.lua` boots them from `ctld.initialize()`, after
`CTLDConfig:load()`. Correct as-is, and now measured rather than assumed.

The CI job in ticket 02 is what keeps this table from going stale.
