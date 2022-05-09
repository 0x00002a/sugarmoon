local M = {}

function M.switch(v)
    return function(lookup)
        local k = lookup[v]
        if k == nil then
            return lookup['_']()
        else
            return k()
        end
    end
end

function M.deep_copy(v)
    return M.switch(type(v)) {
        ['table'] = function()
            local o = {}
            for _, vs in pairs(v) do
                table.insert(o, M.deep_copy(vs))
            end
            return o
        end,
        ['_'] = function() return v end,
    }
end

function M.map(f, tbl)
    local o = {}
    for _, v in pairs(tbl) do
        table.insert(o, f(v))
    end
    return o
end

return M
