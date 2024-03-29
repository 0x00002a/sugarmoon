local util = require("sugarmoon.util")
local M = {}

---@enum ast_type
M.types = {
    LUA_TABLE = 'lua:table',
    IDENT_NAME = 'ident:name',
    LUA_FN = 'lua:fn',
    ASSIGN = 'expr:assign',
    ARG_LIST = 'expr:arglist',
    RAW_WORD = 'raw:word',
    EXPORT = 'decl:export',
    CHUNK = 'expr:chunk',
    ATTR_LOCAL = 'attr:local',
    BLOCK = 'expr:block',
    RAW_LUA = 'raw:lua-code',
    FIELD = 'ast:table-field',
    PRAGMA = 'decl:pragma',
    IMPORT = 'decl:sm:import',
    STRING = 'expr:string',
    IF_STMT = 'stmt:if',
}
M.lang_features = {
    LAMBDAS = 'language:lambdas',
}

---@class ast_node
---@field type ast_type
---@field range { start: number, finish: number } |nil


local ts = M.types

---@param ident_str string
---@return ast_node
function M.mk_name(ident_str)
    if type(ident_str) == 'table' and not ident_str.parts then
        assert(ident_str.type == M.types.IDENT_NAME or ident_str.type == M.types.RAW_WORD)
        return ident_str
    end
    local parts = (type(ident_str) == 'table' and ident_str.parts) or util.str_split(ident_str, '.')
    local sep = util.tbl_reverse(parts)
    return {
        type = M.types.IDENT_NAME,
        base = sep[1],
        context = util.tbl_tail(sep) or {},
    }
end

function M.chunk_prepend(chunk, stmt)
    table.insert(chunk.stmts, 1, stmt)
    return chunk
end

function M.chunk_append(chunk, stmt)
    table.insert(chunk.stmts, stmt)
    return chunk
end

function M.mk_export(names, stmts)
    return {
        type = ts.EXPORT,
        names = names,
        stmts = stmts,
    }
end

function M.mk_if_stmt(cond, body, elifs, else_)
    return {
        type = ts.IF_STMT,
        condition = cond,
        body = body,
        elseifs = elifs,
        else_ = else_,
    }
end

function M.mk_chunk(xs, retr)
    if xs[1] == nil then
        xs = { xs }
    end
    for k, v in pairs(xs) do
        if type(v) == 'string' then
            xs[k] = M.mk_raw_lua(v)
        elseif type(v) == 'number' then
            xs[k] = M.mk_raw_lua(tostring(v))
        end
    end
    local c = {
        type = M.types.CHUNK,
        stmts = xs,
        retr = retr,
    }

    return c
end

---@return ast_node
function M.mk_pragma(content)
    return {
        type = ts.PRAGMA,
        content = content
    }
end

function M.mk_assign(lhs, rhs)
    return {
        type = M.types.ASSIGN,
        lhs = lhs,
        rhs = rhs
    }
end

function M.mk_raw_word(word)
    return {
        type = ts.RAW_WORD,
        word = word,
    }
end

function M.mk_block(stmts)
    return {
        type = ts.BLOCK,
        inner = stmts,
    }
end

function M.mk_raw_lua(code)
    return {
        type = ts.RAW_LUA,
        code = code,
    }
end

function M.mk_tbl_field(k, v)
    if v == nil then
        v = k
        k = nil
    end
    return {
        type = ts.FIELD,
        key = k,
        value = v,
    }
end

function M.mk_tbl(values)
    local ast_values = {}
    for k, v in pairs(values) do
        if type(v) == 'table' and v.type and v.type == ts.FIELD then
            table.insert(ast_values, v)
        else
            table.insert(ast_values, M.mk_tbl_field(k, v))
        end
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
        body = body,
    }
end

function M.add_requires_feat(node, feat)
    assert(type(node) == 'table' and node.type, "input must be an ast node but was: " .. util.to_str(node))
    if not node.required_features then
        node.required_features = {}
    end
    table.insert(node.required_features, feat)
    return node
end

function M.mk_fn_named(name, ...)
    return M.mk_assign(M.mk_name(name), M.mk_fn_annon(...))
end

function M.mk_import(path)
    return {
        type = ts.IMPORT,
        path = path
    }
end

function M.mk_string(content, quotes)
    return {
        type = ts.STRING,
        content = content,
        quotes = quotes
    }
end

---@param node ast_node
---@param start number
---@param finish number
---@return ast_node
function M.located(node, start, finish)
    node.range = { start = start, finish = finish }
    return node
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
        [ts.CHUNK] = keys "values",
        [ts.EXPORT] = key 'target',
        [ts.ATTR_LOCAL] = key 'target',
        [ts.ASSIGN] = function()
            return { node.lhs, node.rhs }
        end,
        [ts.LUA_FN] = key 'body',
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
