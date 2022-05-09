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
}

function M.mk_name(ident_str)
    local sep = util.tbl_reverse(util.str_split(ident_str, '.'))
    return {
        type = M.types.IDENT_NAME,
        base = sep[1],
        context = util.tbl_tail(sep)
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

return M
