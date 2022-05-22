local types = require("sugarmoon.ast").types
local util = require("sugarmoon.util")
local ast = require("sugarmoon.ast")

local M = {}

local function to_lua(c)
    local lookup = {
        [types.ASSIGN] = function()
            assert(c.lhs and c.rhs, debug.traceback("invalid assign: " .. util.to_str(c)))
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
        [types.FIELD] = function()
            local function wrap_key(k)
                if k.type == types.RAW_WORD or k.type == types.RAW_LUA then
                    return to_lua(k)
                else
                    return '[' .. to_lua(k) .. ']'
                end
            end

            local prefix = c.key and (wrap_key(c.key) .. ' = ') or ''
            local v = to_lua(c.value)
            local suffix = v
            if v:sub(-1) ~= ',' then
                suffix = suffix .. ','
            end
            return prefix .. suffix
        end,
        [types.LUA_TABLE] = function()
            return "{" .. (table.concat(util.map(to_lua, c.values), '\n')) .. '}'
        end,
        [types.ARG_LIST] = function()
            return table.concat(util.map(to_lua, c.values), ',')
        end,
        [types.RAW_WORD] = function()
            return c.word
        end,
        [types.LUA_FN] = function()
            local body = (c.body and to_lua(c.body)) or ""
            return 'function' .. '(' .. table.concat(c.args, ',') .. ")\n" .. body .. '\nend'
        end,
        [types.EXPORT] = function()
            if c.stmts then
                return table.concat(util.map(to_lua, c.stmts), '\n')
            else
                return ""
            end
        end,
        [types.CHUNK] = function()
            local postfix = (c.retr and ("\nreturn " .. to_lua(c.retr) .. ' ')) or ""
            return table.concat(util.map(to_lua, c.stmts), '\n') .. postfix
        end,
        [types.ATTR_LOCAL] = function()
            assert(c.target, debug.traceback("invalid attr local: " .. util.to_str(c)))
            return 'local ' .. to_lua(c.target)
        end,
        [types.RAW_LUA] = function()
            return c.code
        end,
        ["_"] = function()
            error(debug.traceback("invalid ast node: " .. util.to_str(c)))
        end
    }
    assert(type(c) == 'table', debug.traceback("node has invalid datatype: " .. type(c) .. ' (' .. util.to_str(c) .. ')'))
    if not next(c) then
        return ""
    end
    assert(c.type, debug.traceback("type cannot be nil: " .. util.to_str(c)))
    return util.switch(c.type)(lookup)
end

local function mk_ctx()
    local ctx = {}
    ctx.__exported = {}
    ctx.__module_name = "__SmModule"

    function ctx:add_export(node)
        for _, name in pairs(node.names) do
            if type(name) == 'string' then
                self.__exported[name] = true
            else
                self.__exported[name.word] = true
            end
        end
    end

    function ctx:_generate_exports()
        local values = {}
        for name, v in pairs(self.__exported) do
            if v then
                local lhs = ast.mk_name(name)
                table.insert(lhs.context, self.__module_name)

                table.insert(values, ast.mk_assign(lhs, ast.mk_name(name)))
            end
        end
        return ast.mk_chunk(values)
    end

    function ctx:wrap(tast)
        return tast
    end

    return ctx
end

local function is_lang_pragma(str)
    return util.starts_with(str, 'language:')
end

local function find_nodes_with_invalid_feats(context_feats, root, out)
    out = out or {}
    local ts = types
    if root.required_features then
        for _, f in ipairs(root.required_features) do
            if not context_feats[f] then
                table.insert(out, { reason = 'missing language feature', node = root, feature = f })
            end
        end
    end
    util.switch(root.type) {
        [ts.CHUNK] = function()
            local ctx_feats = util.deep_copy(context_feats)
            for _, s in pairs(root.stmts) do
                if s.type == ts.PRAGMA and is_lang_pragma(s.content) then
                    ctx_feats[s.content] = true
                end
            end
            for _, s in pairs(root.stmts) do
                find_nodes_with_invalid_feats(ctx_feats, s, out)
            end
            if root.retr then
                find_nodes_with_invalid_feats(ctx_feats, root.retr, out)
            end
        end,
        ["_"] = function()
            local kids = ast.children(root)
            if kids then
                for _, c in pairs(ast.children(root)) do
                    find_nodes_with_invalid_feats(context_feats, c, out)
                end
            end
        end
    }
    return out
end

local function populate_exports(ast, ctx)
    assert(ctx)

    util.switch(ast.type) {
        [types.EXPORT] = function()
            ctx:add_export(ast)
        end,
        [types.CHUNK] = function()
            for _, v in pairs(ast.stmts) do
                populate_exports(v, ctx)
            end
        end,
        ["_"] = function() end
    }
end

function M.find_invalid_nodes(root, compile_ctx)
    compile_ctx = compile_ctx or {}
    compile_ctx.global_feats = compile_ctx.global_feats or {}
    local out = {}
    find_nodes_with_invalid_feats(compile_ctx.global_feats or {}, root, out)
    return out
end

function M.to_lua(c, compile_ctx)
    compile_ctx = compile_ctx or {}
    local invalid = M.find_invalid_nodes(c, compile_ctx)
    if #invalid > 0 then
        return nil, invalid
    end
    local ctx = mk_ctx()
    populate_exports(c, ctx)
    c = ctx:wrap(c)
    local content = to_lua(c)
    return content
end

return M
