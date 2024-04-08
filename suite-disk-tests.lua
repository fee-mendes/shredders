local KByte <const> = 1000
local MByte <const> = KByte * 1000
local GByte <const> = MByte * 1000
local TByte <const> = GByte * 1000

-- 124 megabytes per second is roughly one gigabit
local gbit_per_sec <const> = 124 * MByte
-- arbitrary "n gigabits per second" warm rate to avoid eviction issues with
-- extstore.
-- requires that we also set sleep rate to 100ms
local warm_write_rate = (gbit_per_sec * 12) / 10

local base_arg = "-v -A -r -m 114100 -c 4096 --lock-memory --threads 14 -u scylla -C -o ext_path=/mnt/file:3400G "

local basic_fill_size = 2.8 * TByte
local basic_item_size = 8 * KByte
-- For quick tests, uncomment these.
--local basic_fill_size = 1 * GByte
--local basic_item_size = 1 * KByte
local basic_item_count = math.floor(basic_fill_size / basic_item_size)

local test_count = math.floor((1 * GByte) / basic_item_size)

-- 'a' gets passed back into the function t
-- because the perf tests were structured in a ramp structure that edits a
-- between runs. not used for extstore right now but I might enable it again
-- so leaving it in this format.
local tests = {
    -- basic prefill then random overwrite + random reads load pattern
    -- this is a semi-worst case scenario
    basic = {
        s = base_arg, 
        w = { { limit = basic_item_count, vsize = basic_item_size, prefix = "disk", shuffle = true, flush_after = warm_write_rate, sleep = 100 } },

        a = { cli = 25, rate = 2500000, pipes = 16, prefix = "disk", limit = basic_item_count, vsize = basic_item_size },
        t = function(thr, wthr, o)
	    mcs.add(thr, { func = "perfrun_metaget_pipe", clients = o.cli, rate_limit = o.rate, init = true }, o)
        end,
    },
}

local test_list = {
    "basic",
}

return {
    tests = tests,
    testset = test_list,
}
