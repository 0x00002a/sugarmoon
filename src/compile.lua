local types = require("ast").types
local util = require("util")

local M = {}

function M.to_lua(c)
    local lookup = {
        [types.ASSIGN] = function()
            return M.to_lua(c.lhs) .. '=' .. M.to_lua(c.rhs)
        end,
        [types.IDENT_NAME] = function()
            return c.value
        end,
        [types.LUA_TABLE] = function()
            return "{" .. ((c.values and table.concat(util.map(M.to_lua, c.values), ',')) or "") .. '}'
        end,
        [types.ARG_LIST] = function()
            return util.map(M.to_lua, c.values):concat(',')
        end,
        [types.RAW_WORD] = function()
            return c.word
        end,
        [types.LUA_FN] = function()
            return 'function' .. '(' .. M.to_lua(c.args) .. ")" .. c.body .. 'end'
        end,
        ["_"] = function()
            error("invalid type: " .. c.type)
        end
    }
    return util.switch(c.type)(lookup)
end

return M
