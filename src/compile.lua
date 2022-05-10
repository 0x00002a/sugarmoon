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
            local prefix = ''
            if c.context then
                local context = util.tbl_reverse(util.deep_copy(c.context))
                table.insert(context, c.base)
                return table.concat(context, '.')
            end
            return prefix .. c.base
        end,
        [types.LUA_TABLE] = function()
            return "{" .. (table.concat(util.map(to_lua, c.values), ',')) .. '}'
        end,
        [types.ARG_LIST] = function()
            return table.concat(util.map(to_lua, c.values), ',')
        end,
        [types.RAW_WORD] = function()
            return c.word
        end,
        [types.LUA_FN] = function()
            local body = (c.body and to_lua(c.body)) or ""
            return 'function' .. '(' .. table.concat(c.args, ',') .. ")" .. body .. 'end'
        end,
        [types.EXPORT] = function()
            return to_lua(c.target)
        end,
        [types.CHUNK] = function()
            local postfix = (c.retr and "return " .. to_lua(c.retr)) or ""
            return table.concat(util.map(to_lua, c.stmts), '\n') .. postfix
        end,
        [types.ATTR_LOCAL] = function()
            return 'local ' .. to_lua(c.target)
        end,
        [types.RAW_LUA] = function()
            return c.code
        end,
        ["_"] = function()
            error(debug.traceback("invalid ast node: " .. util.to_str(c)))
        end
    }
    assert(type(c) == 'table', debug.traceback("invalid node type: " .. util.to_str(c)))
    if not next(c) then
        return ""
    end
    assert(c.type, debug.traceback("type cannot be nil"))
    return util.switch(c.type)(lookup)
end

local function mk_ctx()
    local ctx = {}
    ctx.__exported = {}
    ctx.__module_name = "__SmModule"

    function ctx:add_export(node)
        local found = ast.find_first({ types.EXPORT, types.ASSIGN }, node)
        assert(found, 'invalid node for export: ' .. util.to_str(node))
        local name = found.lhs
        self.__exported[name] = true
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
        return ast.mk_chunk(values)
    end

    function ctx:wrap(tast)
        local modname = ast.mk_name(self.__module_name)
        tast = ast.mk_chunk(tast, modname)

        local header = ast.mk_local(ast.mk_assign(modname, ast.mk_tbl({})))
        tast:prepend(header)
        local exports = self:_generate_exports()
        tast:append(exports)

        return tast
    end

    return ctx
end

local function populate_exports(ast, ctx)
    assert(ctx)

    util.switch(ast.type) {
        [types.EXPORT] = function()
            ctx:add_export(ast.target)
        end,
        [types.CHUNK] = function()
            for _, v in pairs(ast.stmts) do
                populate_exports(v, ctx)
            end
        end,
        ["_"] = function() end
    }
end

function M.to_lua(c)
    local ctx = mk_ctx()
    populate_exports(c, ctx)
    c = ctx:wrap(c)
    local content = to_lua(c)
    return content
end

return M
