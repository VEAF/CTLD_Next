---@diagnostic disable
-- tests/ci/smoke/load_built_ctld.lua
-- Load the *built* CTLD.lua under Lua 5.1 with the DCS stubs, and fail if it does not come up.
--
-- Usage (from the repo root):  lua5.1 tests/ci/smoke/load_built_ctld.lua [path/to/CTLD.lua]
--
-- Why this exists — FIX-BUILT-FILE-DOES-NOT-LOAD. CTLD.lua is the only artefact this project
-- ships, and until this file it was the only one nothing executed:
--
--   * lua-lint syntax-checks src/ per module with `luac5.1 -p` — syntax, never execution, never
--     the merged file.
--   * busted loads src/ through tests/ci/helpers/loader.lua, which calls CTLDConfig.get():load()
--     *before* any manager and never loads src/scenes/ at all — so the suite cannot reproduce the
--     shipped ordering (scenes self-registering against an unloaded config) even in principle.
--   * the Merge Build job asserts CTLD.lua exists and is non-empty.
--
-- 2.0.0-rc8 passed all three and raised on load in every mission that ran it.
--
-- This runner deliberately does NOT touch tests/ci/helpers/loader.lua or init.lua: loading src/
-- modules is exactly the habit that hid the bug. Stubs only, then the merged file.
-- ============================================================

local BUILT = arg[1] or "CTLD.lua"

local function die(...)
    io.stderr:write("SMOKE FAIL: ", string.format(...), "\n")
    os.exit(1)
end

-- ── 1. DCS API surface ───────────────────────────────────────
-- The same stubs busted uses, on purpose: a private copy here would rot, and a global the engine
-- needs should be missing in one place only. If this runner reports a nil global, add it there.
local okStubs, errStubs = pcall(dofile, "tests/ci/helpers/dcs_stubs.lua")
if not okStubs then
    die("could not load tests/ci/helpers/dcs_stubs.lua (run me from the repo root): %s", tostring(errStubs))
end

-- CTLD writes its debug log through lfs.writedir(); DCS provides lfs, a bare interpreter does not.
lfs = lfs or { writedir = function() return "." end, mkdir = function() end }

-- ── 2. Run the merged file exactly as DCS would ──────────────
local chunk, loadErr = loadfile(BUILT)
if not chunk then
    die("%s does not even parse: %s", BUILT, tostring(loadErr))
end

local ok, err = xpcall(chunk, function(e)
    return tostring(e) .. "\n" .. debug.traceback("", 2)
end)
if not ok then
    die("%s raised while loading:\n%s", BUILT, tostring(err))
end

-- ── 3. Prove it came up, rather than merely not exploding ────
-- Absence of an error is not enough: a future pcall swallowing the failure inside initialize()
-- would leave this green while shipping a dead engine. Both observables below already exist —
-- nothing is added to the product for the sake of this check.

if type(ctld) ~= "table" then
    die("the global `ctld` table does not exist after loading %s", BUILT)
end

if not (CTLDConfig and CTLDConfig.get and CTLDConfig.get().isLoaded) then
    die("ctld.initialize() did not load the configuration (CTLDConfig.isLoaded is not true)")
end

-- The five built-in scene models are what today's bug destroys: they self-register during the
-- main chunk, and that registration is what raised. Count them rather than trusting silence.
local EXPECTED_SCENES = 5
if not CTLDSceneManager then
    die("CTLDSceneManager is missing after loading %s", BUILT)
end
local models = CTLDSceneManager.getInstance()._models or {}
local n = 0
for _ in pairs(models) do n = n + 1 end
if n < EXPECTED_SCENES then
    die("only %d built-in scene model(s) registered, expected at least %d — "
        .. "a scene file failed to self-register during the main chunk", n, EXPECTED_SCENES)
end

print(string.format("SMOKE OK: %s loads, config is loaded, %d scene model(s) registered.", BUILT, n))
