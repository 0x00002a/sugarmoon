local types = require("ast").types
local util = require("util")
local ast = require("ast")

local M = {}

local function to_lua(c)
    local lookup = {
        [types.ASSIGN] = function()
            return to_lua(c.lhs) .. '=' .. to_lua(c.rhs)
        end,
        [types.IDENT_NAME] = function()
            return c.value
        end,
        [types.LUA_TABLE] = function()
            return "{" .. ((c.values and table.concat(util.map(to_lua, c.values), ',')) or "") .. '}'
        end,
        [types.ARG_LIST] = function()
            return util.map(to_lua, c.values):concat(',')
        end,
        [types.RAW_WORD] = function()
            return c.word
        end,
        [types.LUA_FN] = function()
            return 'function' .. '(' .. to_lua(c.args) .. ")" .. c.body .. 'end'
        end,
        [types.EXPORT] = function()
        end,
        [types.NODES] = function()
            return table.concat(util.map(to_lua, c.values), '')
        end,
        ["_"] = function()
            error("invalid type: " .. c.type)
        end
    }
    return util.switch(c.type)(lookup)
end

local function mk_ctx()
    local ctx = {}
    ctx.__exported = {}
    ctx.__module_name = "__SmModule"

    function ctx:add_export(node)
        return util.switch(node.type) {
            ["_"] = function()
                self.__exported[node.name] = true
            end,
        }
    end

    function ctx:_generate_exports()
        local values = {}
        for name, v in pairs(self.__exported) do
            if v then
                local lhs = util.deep_copy(name)
                table.insert(lhs.context, self.__module_name)

                table.insert(values, ast.mk_assign(lhs, name))
            end
        end
        return ast.mk_nodes(values)
    end

    function ctx:wrap(body)
        local modname = ast.mk_name(self.__module_name)

        local header = ast.mk_assign(modname, ast.mk_tbl({}))
        local exports = self:_generate_exports()

        body = to_lua(header) .. body .. to_lua(exports)
    end

    return ctx
end

local function populate_exports(ast, ctx)
    assert(ctx)

    util.switch(ast.type) {
        [types.EXPORT] = function()
            ctx:add_export(ctx.target)
        end,
        ["_"] = function() end
    }
end

function M.to_lua(c)
    local content = to_lua(c)
    local ctx = mk_ctx()
    populate_exports(c, ctx)
    return ctx:wrap(content)
end

return M
