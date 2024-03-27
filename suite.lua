require("suite-util")
require("suite-lib")
require("suite-performance-lib")
local test_p = require("suite-performance-tests")
local test_ext = require("suite-extstore-tests")

function help()
    local msg =[[
        time (30) (how long to run each sub test)
        threads (5) (number of mcshredder threads for test load)
        suite (nil) (override the test suite to run)
        keep (false) (whether ot leave memcached's running after stability test)
        backends (list) ('-' separated list of perf. test proxy configs to run)
        clients (list) ('-' separated list of perf. test client configs to run)
        set (list) ('-' separated list of stability test sets to run)
        pfx (list) ('-' separated list of stability proxy backend prefixes to run)
        test (list) ('-' separated list of stability sub-tests to run)

        see suite-*-.lua files for the various default lists.
    ]]
    print(msg)
end

function _split_arg(a)
    local t = {}
    for name in string.gmatch(a, '([^-]+)') do
        table.insert(t, name)
    end
    return t
end

function _split_arghash(a)
    local t = {}
    for name in string.gmatch(a, '([^-]+)') do
        t[name] = true
    end
    return t
end

function config(a)
    local o = {
        threads = 32,
        time = 1800,
        keep = false, -- whether or not to leave mc running post-test.
    }
    if a["threads"] ~= nil then
        print("[init] overriding: test threadcount")
        o.threads = a.threads
    end
    if a["time"] ~= nil then
        print("[init] overriding: test time")
        o.time = tonumber(a.time)
    end
    if a["set"] ~= nil then
        print("[init] overriding: test set")
        o.set = _split_arghash(a["set"])
    end
    if a["pfx"] ~= nil then
        print("[init] overriding: test prefix")
        o.pfx = _split_arg(a["pfx"])
    end
    if a["test"] ~= nil then
        print("[init] overriding: test")
        o.test = _split_arghash(a["test"])
    end
    if a["keep"] ~= nil then
        print("[init] keeping memcached running post-test")
        o.keep = true
    end
    if a["backends"] ~= nil then
        print("[init] overriding performance backend list")
        o.backends = _split_arg(a["backends"])
    end
    if a["clients"] ~= nil then
        print("[init] overriding performance clients list")
        o.clients = _split_arg(a["clients"])
    end
    if a["extset"] ~= nil then
        -- hope I can refactor these into a shared pattern soon...
        print("[init] overriding extstore test list")
        o.extset = _split_arg(a["extset"])
    end
    if a["api2"] ~= nil then
        print("[init] running in api2 mode")
        o.api2 = true
    end

    local threads = {}
    for i=1,o.threads do
        table.insert(threads, mcs.thread())
    end
    o["testthr"] = threads
    o["warmthr"] = mcs.thread()
    o["statsthr"] = mcs.thread()
    o["maintthr"] = mcs.thread()

    local suites = { suite_stability }

    if a["suite"] ~= nil then
        print("[init] overriding test suite: " .. a["suite"])
        _G["test_" .. a["suite"]](o)
    else
        test_extstore(o)
    end
end

--
-- TEST PLANS --
--

--
-- extstore test runner
--

-- most code inherited/modified from the performance runner.
function test_ext_warm(thread, client)
    plog("LOG", "INFO", "warming")
    local c = client
    if c == nil or #c == 0 then
        -- allow empty lists to skip any warming.
        return
    end
    for _, conf in ipairs(c) do
        mcs.add_custom(thread, { func = "perf_warm" }, conf)
    end
    mcs.shredder({thread})
    plog("LOG", "INFO", "warming end")
end

-- for extstore tests we pass the warm thread back into the main workload
-- so we can make single threaded "writer" threads to emulate certain load
-- patterns and to allow repeatable data loading in general.
function test_ext_run_test(o, test)
    local testthr = o.testthr
    local statthr = o.statsthr
    local warmthr = o.warmthr

    -- TODO: really need to make add auto-track threads.
    local allthr = {statthr, warmthr}
    for _, t in ipairs(testthr) do
        table.insert(allthr, t)
    end

    local stats_arg = { stats = { "cmd_get", "cmd_set"}, track = { "evictions" } } --, "extstore_bytes_read", "extstore_objects_read", "extstore_objects_written" }, track = { "extstore_bytes_written", "extstore_bytes_fragmented", "extstore_bytes_used", "extstore_io_queue", "extstore_page_allocs", "extstore_page_reclaims", "extstore_page_evictions", "extstore_pages_free", "evictions" } }

    -- copy the argument table since we modify it at runtime.
    -- want to do this better but it does complicate the code a lot...
    local a = shallow_copy(test.a)

    test.t(testthr, warmthr, a)
    -- one set of funcs on each test thread that ships history
    -- one func that reads the history and summarizes every second.
    mcs.add(testthr, { func = "perfrun_stats_out", rate_limit = 1, clients = 1 })
    mcs.add_custom(statthr, { func = "perfrun_stats_gather" }, { threads = o.threads })
    -- specifically for tracking 'stats' counters
    mcs.add(statthr, { func = "stat_sample", clients = 1, rate_limit = 1 }, stats_arg)
    -- TODO: give the ctx a true/false return via a command.
    mcs.shredder(allthr, o.time)

    -- grab stats snapshot before the server is stopped
    mcs.add_custom(statthr, { func = "full_stats" }, {})
    mcs.shredder({statthr})
end

function test_extstore(o)
    if o.extset then
        test_ext.testset = o.extset
    end

    for _, tconfig in ipairs(test_ext.testset) do
        local t = test_ext.tests[tconfig]
        -- run test
        plog("START", tconfig)
        test_ext_warm(o.warmthr, t.w)
        test_ext_run_test(o, t)
        plog("END")
    end
end

