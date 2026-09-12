---@diagnostic disable
-- tests/ci/unit/log_pre_init_spec.lua
-- busted specs for ctld.utils.log() against an unloaded config — FIX-BUILT-FILE-DOES-NOT-LOAD.
--
-- Why this file exists. The shipped CTLD.lua self-registers five scene models during its **main
-- chunk** (`CTLDSceneManager.getInstance():registerSceneModel(farpScene)` and friends), which logs
-- an INFO line — all of it before ctld.initialize() has loaded any config. ctld.utils.log used to
-- read ctld.gs("debugScreenLog") unguarded, and once FIX-CONFIG-NOT-LOADED-GUARD made that read
-- raise, the raise aborted the whole file: CTLD 2.0.0-rc8 does not load at all.
--
-- The shared helper (tests/ci/helpers/loader.lua) calls CTLDConfig.get():load() before loading any
-- manager and never loads src/scenes/, so the suite could not reproduce that ordering in principle.
-- Hence a spec of its own that resets the config to its unloaded state on purpose.
-- ============================================================

describe("ctld.utils.log before ctld.initialize()", function()

    local savedInstance

    before_each(function()
        savedInstance = CTLDConfig._instance
        ctld.configUser      = nil
        ctld.yamlConfigDatas = nil
        CTLDConfig._instance = nil
        CTLDConfig.get()   -- isLoaded = false, deliberately no :load()
    end)

    -- Same hazard, same remedy as config_spec.lua's "not loaded" block: leaving CTLDConfig
    -- unloaded here fails every later spec in the process, and busted's file order is a directory
    -- hash on Linux — so the mass failure would be unreproducible locally.
    after_each(function()
        ctld.configUser      = nil
        CTLDConfig._instance = savedInstance
        if CTLDConfig._instance == nil then
            CTLDConfig.get():load()
        end
    end)

    it("does not raise", function()
        assert.has_no_error(function() ctld.utils.log("INFO", "hello %s", "world") end)
    end)

    it("still reaches env.info — the only place a pre-init diagnosis can appear", function()
        local seen = {}
        local realInfo = env.info
        env.info = function(m) seen[#seen + 1] = m end
        pcall(ctld.utils.log, "INFO", "hello %s", "world")
        env.info = realInfo
        assert.equals(1, #seen)
        assert.equals("[CTLD][INFO] hello world", seen[1])
    end)

    -- The reported call path, one level up from the logger: this is what the main chunk does when
    -- a scene file self-registers.
    --
    -- Deliberately NOT `CTLDSceneManager.getInstance()`. Its singleton is a module-local upvalue
    -- with no reset seam, and `jtac_manager_spec.lua` already calls `getInstance()` — so depending
    -- on busted's file order (a directory hash on Linux, not stable between runs) this spec would
    -- get a manager that was built long ago, never re-enter `_init`, and pass whether or not the
    -- bug is present. Building the instance the way `getInstance()` builds its first one exercises
    -- the same `_init` → `ctld.utils.log` path, deterministically.
    it("a scene manager can initialize — the path a self-registering scene file takes", function()
        assert.has_no_error(function()
            setmetatable({}, CTLDSceneManager):_init()
        end)
    end)

end)

describe("ctld.utils.log once the config is loaded", function()

    -- The guard added for the pre-init case must not quietly disable the feature it guards.
    -- These two assert the screen-log branch still works exactly as before, both ways.

    local borrowed
    local calls
    local realOutText

    before_each(function()
        calls = {}
        realOutText = trigger.action.outText
        trigger.action.outText = function(msg, duration)
            calls[#calls + 1] = { msg = msg, duration = duration }
        end
    end)

    after_each(function()
        trigger.action.outText = realOutText
        if borrowed then borrowed:restore(); borrowed = nil end
    end)

    it("mirrors the line on screen when debugScreenLog is true", function()
        borrowed = ctldTestSettings.borrow({ debugScreenLog = true, debugScreenLogDuration = 42 })
        ctld.utils.log("WARN", "on screen")
        assert.equals(1, #calls)
        assert.equals("[CTLD][WARN] on screen", calls[1].msg)
        assert.equals(42, calls[1].duration)
    end)

    it("stays off screen when debugScreenLog is false", function()
        borrowed = ctldTestSettings.borrow({ debugScreenLog = false })
        ctld.utils.log("WARN", "log only")
        assert.equals(0, #calls)
    end)

end)
