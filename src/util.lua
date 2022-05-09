local lpeg = require("lpeg")
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

function M.str_split(s, ch)
    local sep = lpeg.P(ch)
    local el = lpeg.C((1 - sep) ^ 0)
    return lpeg.match(lpeg.Ct(el * (sep * el) ^ 0), s)
end

function M.tbl_reverse(tbl)
    if not tbl then
        return nil
    end
    local len = #tbl
    for i = 1, math.floor(#tbl / 2) do
        local v = tbl[i]
        local other = len - i + 1
        tbl[i] = tbl[other]
        tbl[other] = v
    end
    return tbl
end

function M.tbl_tail(tbl)
    if #tbl < 2 then
        return nil
    end
    local o = {}
    for i = 2, #tbl do
        table.insert(o, tbl[i])
    end
    return o
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
