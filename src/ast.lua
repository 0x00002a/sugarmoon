local util = require("util")
local M = {}

M.types = {
    LUA_TABLE = 'lua:table',
    IDENT_NAME = 'ident:name',
    LUA_FN = 'lua:fn',
    ASSIGN = 'expr:assign',
    ARG_LIST = 'expr:arglist',
    RAW_WORD = 'raw:word',
    EXPORT = 'decl:export',
    NODES = 'ast:nodes',
    ATTR_LOCAL = 'attr:local',
}
local ts = M.types

function M.mk_name(ident_str)
    if type(ident_str) == 'table' then
        assert(ident_str.type == M.types.IDENT_NAME)
        return ident_str
    end
    local sep = util.tbl_reverse(util.str_split(ident_str, '.'))
    return {
        type = M.types.IDENT_NAME,
        base = sep[1],
        context = util.tbl_tail(sep) or {},
    }
end

function M.mk_nodes(xs)
    return {
        type = M.types.NODES,
        values = xs
    }
end

function M.mk_assign(lhs, rhs)
    return {
        type = M.types.ASSIGN,
        lhs = lhs,
        rhs = rhs
    }
end

function M.mk_tbl(values)
    local ast_values = {}
    for k, v in pairs(values) do
        table.insert(ast_values, M.mk_assign(M.mk_name(k), v))
    end
    return {
        type = M.types.LUA_TABLE,
        values = ast_values,
    }
end

function M.mk_arglist(values)
    return {
        type = M.types.ARG_LIST,
        values = values
    }
end

function M.mk_local(target)
    return {
        type = M.types.ATTR_LOCAL,
        target = target
    }
end

function M.mk_fn_annon(args, body)
    return {
        type = M.types.LUA_FN,
        args = args or {},
        body = body or "",
    }
end

function M.mk_fn_named(name, ...)
    return M.mk_assign(M.mk_name(name), M.mk_fn_annon(...))
end

function M.children(node)
    assert(node, debug.traceback("node cannot be nil"))
    local function keys(v)
        return function()
            return node[v]
        end
    end

    local function key(v)
        return function()
            return { node[v] }
        end
    end

    return util.switch(node.type) {
        [ts.NODES] = keys "values",
        [ts.EXPORT] = key 'target',
        [ts.ATTR_LOCAL] = key 'target',
        [ts.ASSIGN] = function()
            return { node.lhs, node.rhs }
        end,
        ["_"] = function()
            return nil
        end
    }

end

local function check_key(tbl, kh)
    assert(tbl[kh], "invalid ast node (missing " .. kh .. '): ' .. util.to_str(tbl))
end

function M.find_first(search, ast)
    assert(search and #search > 0, "empty search space")
    local kids = M.children(ast)
    if not kids then
        return nil
    end
    local target = search[1]
    local next_targets = util.tbl_tail(search)
    for _, k in pairs(kids) do
        check_key(k, 'type')
        if k.type:gmatch(target) then
            if not next_targets then
                return ast
            else
                local rs = M.find_first(next_targets, k)
                if rs then
                    return rs
                end
            end
        end
    end
    return nil
end

return M
