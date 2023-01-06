local lpeg = require("lpeglabel")
local M = {}



---@generic T
---@generic C
---@param v T
---@return fun(lookup: {[T]: (fun(): C)|C}): C
function M.switch(v)
    return function(lookup)
        local k = lookup[v]
        if k == nil then
            return lookup['_']()
        elseif type(k) == 'function' then
            return k()
        else
            return k
        end
    end
end

---@param s string
---@param ch string
---@return string[]
function M.str_split(s, ch)
    local sep = lpeg.P(ch)
    local el = lpeg.C((1 - sep) ^ 0)
    return lpeg.match(lpeg.Ct(el * (sep * el) ^ 0), s)
end

---@generic T
---@param tbl T[]
---@return T[]
function M.tbl_reverse(tbl)
    assert(tbl ~= nil)
    local len = #tbl
    for i = 1, math.floor(#tbl / 2) do
        local v = tbl[i]
        local other = len - i + 1
        tbl[i] = tbl[other]
        tbl[other] = v
    end
    return tbl
end

function M.rstrip(str)
    assert(type(str) == 'string', "rstrip got an invalid type: " .. type(str))

    local spaces = (lpeg.P ' ') ^ 1 * lpeg.P(-1)
    local p = lpeg.Ct((spaces + lpeg.C(lpeg.P(1))) ^ 0) / function(t) return table.concat(t, '') end
    return lpeg.match(p, str)
end

function M.starts_with(str, txt)
    return lpeg.match(lpeg.P(txt) * lpeg.P(str:len() - txt:len()) * lpeg.P(-1), str) ~= nil
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
            for k, vs in pairs(v) do
                o[k] = M.deep_copy(vs)
            end
            return o
        end,
        ['_'] = function() return v end,
    }
end

---@param v function|number|string|nil|table
---@param indent number|nil
---@return string
function M.to_str(v, indent)
    indent = indent or 0
    local next_ids = indent + 4
    local ids = string.rep(' ', indent)
    return M.switch(type(v)) {
        ['string'] = function()
            return '"' .. v .. '"'
        end,
        ['number'] = function() return tostring(v) end,
        ['nil'] = function() return "nil" end,
        ['table'] = function()
            local last_ids = (indent > 3 and string.rep(' ', indent - 4)) or ids
            local vs = ""
            for k, val in pairs(v) do
                vs = vs .. ids .. '[' .. M.to_str(k) .. ']' .. ' = ' .. M.to_str(val, next_ids) .. ',\n'
            end
            return '{\n' .. vs .. last_ids .. '}'
        end,
        ['function'] = function()
            return string.format("<fn: %p>", v)
        end,
        ['_'] = function()
            error("unhandled type: " .. type(v))
        end
    }
end

function M.tbl_find(tbl, pred)
    for _, v in pairs(tbl) do
        if (type(pred) == 'function' and pred(v)) or v == pred then
            return v
        end
    end
    return nil
end

---@generic T
---@generic C
---@param f fun(t: T): C
---@param tbl T[]
---@return C[]
function M.map(f, tbl)
    assert(tbl ~= nil)
    local o = {}
    for _, v in pairs(tbl) do
        local rs = f(v)
        assert(rs, debug.traceback("return value cannot be nil"))
        table.insert(o, rs)
    end
    return o
end

return M
