-- FIXME: should load these during config stage via callouts to dig.
-- they don't change in practice though, so low priority.
local NODE_IPS <const> = { '172.31.19.254' }

function nodeips()
    return NODE_IPS
end

function plog(...)
    io.write(os.date("%a %b %e %H:%M:%S | "))
    io.write(table.concat({...}, " | "))
    io.write("\n")
    io.flush()
end

function shallow_copy(a)
    local c = {}
    for key, val in pairs(a) do
        c[key] = val
    end
    return c
end
