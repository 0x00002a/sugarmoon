local lpeg = require("lpeg")
lpeg.locale(lpeg)

local util = require("util")
local types = require("ast").types
local ast = require("ast")
local P = lpeg.P
local S = lpeg.S
local R = lpeg.R
local C = lpeg.C
local V = lpeg.V
local Ct = lpeg.Ct
local Cg = lpeg.Cg
local Cc = lpeg.Cc

local M = {}


M.keywords = {}

local until_p = function(p) return Cg((1 - p) ^ 0) * p end
local comment = (P '--[[' * Cg(until_p(P ']]--'), 'comment'))
    + (P '--' * Cg(until_p(P '\n'), 'comment'))
local space = (lpeg.space + P '\n' + comment) ^ 0

local function tkn(s)
    return space * P(s) * space
end

local function op(ch)
    return tkn(ch)
end

local function kw(word)
    M.keywords[word] = true
    return space * P(word) * space
end

local function sep_by(p, ch)
    return p * ((ch * p) ^ 0)
end

local function void(p)
    return p / 0
end

local function maybe(p)
    return p ^ -1
end

local function maybe_local(p)
    local local_p = (kw "local" * space * p) / ast.mk_local
    return local_p + p
end

local open_brace = P "("
local close_brace = P ")"

local identchar = R("AZ", "az") + P "_"
local identword = identchar * ((identchar + R "09") ^ 0) / function(c) return { type = types.RAW_WORD, word = c } end

local ident_name = Ct(identword * (P '.' * identword) ^ 0) / function(c)
    c = util.map(function(v)
        if type(v) == 'table' then
            return v.word
        else
            return v
        end
    end, c)
    return ast.mk_name { parts = c }
end


local commasep_list = Ct(identword * ((void(space * P "," * space) * identword) ^ 0))
    / function(c) return { type = types.ARG_LIST, values = c } end
local function mk_fn_args()
    local function to_ast(c)
        if not c[1] then
            return ast.mk_arglist({})
        end
        local args = {}
        for _, v in pairs(c[1].values) do
            table.insert(args, v.word)
        end
        return ast.mk_arglist(args)
    end

    local p = Ct(open_brace * space * commasep_list ^ -1 * space * close_brace) / to_ast
    return p
end

local fn_args = mk_fn_args()

local function mk_lua_fn(assign)
    local function to_ast(c)
        local args = c.args.values
        if c.name then
            return ast.mk_fn_named(c.name, args, c.body)
        else
            return ast.mk_fn_annon(args, c.body)
        end
    end

    local function do_match(name)
        local name_pat = (not name and ident_name) or (name ~= '' and lpeg.Cc(name)) or lpeg.Cc(nil)
        local pat =
        void(kw("function") * space)
            * (Cg(name_pat, "name"))
            * space
            * (Cg(fn_args, "args"))
            * (Cg(until_p(P "end"), "body"))
        return Ct(pat) / to_ast
    end

    local match_annon = assign(do_match)
    local match_named = do_match()
    return maybe_local(match_named + match_annon)
end

local function lua_table(assignment)
    return Ct(void(P "{" * space) * (assignment ^ 0) * void(space * P "}"))
        / function(c)
            return {
                type = types.LUA_TABLE,
                values = c
            }
        end
end

local function assignment(rvalue)
    return Ct(ident_name * void(space * op "=" * space) * rvalue) / function(c)
        return {
            type = types.ASSIGN,
            lhs = c[1],
            rhs = c[2]
        }
    end
end

local lua_function = mk_lua_fn(function(do_mk)
    return assignment(do_mk(""))
end)

local function string_literal()
    local escape_seqs = util.map(function(s) return P '\\' * s end, {
        P 'a',
        P 'n',
        P 'r',
        P 't',
        P 'v',
        P '\\',
        P '"',
        P "'",
        P '\n',
        R "09" ^ 3,
    })
    local valid_ch = lpeg.alnum
    for _, p in pairs(escape_seqs) do
        valid_ch = valid_ch + p
    end
    local function match_with(p)
        return P(p) * ((P("\\" .. p)) + (1 - P(p))) ^ 0 * P(p)
    end

    local dbl = match_with '"'
    local single = match_with "'"
    local long = P "[[" * (valid_ch + P '\n') ^ 0 * P "]]"
    return dbl + single + long
end

local number = lpeg.digit ^ 1

local function binop()
    local ops = {
        'and', 'or', '+', '-', '/', '*', '^', '%', '..', '<', '<=', '>', '>=', '==', '~=',
    }
    local out = nil
    for _, p in pairs(ops) do
        p = tkn(p)
        if not out then
            out = p
        else
            out = out + p
        end
    end
    return out
end

local function to_ast_field(c)
    if c.lhs then
        return ast.mk_assign(c.lhs, c.rhs)
    else
        error("not implemented")
    end
end

local function to_ast_func(c)
    return ast.mk_fn_annon(c.args.values, c.body)
end

local function to_ast_func_named(c)
    return ast.mk_fn_named(c.name, c.args.values, c.body)
end

local function to_ast_tbl(c)
    return ast.mk_tbl(c.fields or {})
end

local function to_ast_assign(c)
    local name = (c.lhs.type == types.RAW_WORD and ast.mk_name(c.lhs.word)) or c.lhs
    return ast.mk_assign(name, c.rhs)
end

local function to_ast_block(c)
    return ast.mk_block(c.inner)
end

local function to_raw_lua(c)
    return ast.mk_raw_lua(c)
end

local function to_ast_chunk(c)
    local stmts = {}
    for _, v in ipairs(c) do
        if v.stmt then
            table.insert(stmts, v.stmt)
        end
    end
    local retr = c[#c] and c[#c].retr
    return ast.mk_chunk(stmts, retr)
end

local function to_ast_assign_local(c)
    local lhs = c.lhs
    local rhs = c.rhs or ast.mk_raw_lua('nil')
    return ast.mk_local(ast.mk_assign(lhs, rhs))
end

local function as_local(inner)
    return function(c)
        return ast.mk_local(inner(c))
    end
end

local complete_grammer = {
    'chunk';
    chunk = Ct(
        ((Ct(Cg(V "stat", 'stmt')) * maybe(tkn ";")) ^ 1 * space * Ct(maybe((Cg(V "laststat", 'retr')) * maybe(tkn ";"))))
        + Ct(space * Cg(V 'laststat', 'retr') * maybe(tkn ';'))) / to_ast_chunk,
    block = V "chunk",
    stat = Ct(kw 'do' * space * maybe(Cg(V 'block', 'inner')) * space * kw 'end') / to_ast_block
        + C(kw 'while' * space * V 'expv' * space * kw 'do' * space * maybe(V 'block') * space * kw 'end') / to_raw_lua
        + C(kw 'repeat' * space * maybe(V 'block') * space * kw 'until' * space * V 'expv') / to_raw_lua
        + C(kw 'if' * space * V 'expv' * kw 'then' * maybe(V 'block')
            * ((kw 'elseif' * space * kw 'then' * space * maybe(V 'block')) ^ 0)
            * maybe(kw 'else' * maybe(V 'block'))
            * kw 'end') / to_raw_lua
        + C(kw 'for' * space * identword * op '=' * V 'expv' * tkn ',' * sep_by(V 'expv', tkn ',') * space * kw 'do' * maybe(V 'block') * kw 'end') / to_raw_lua
        + C(kw 'for' * V 'namelist' * kw 'in' * V 'explist' * kw 'do' * maybe(V 'block') * kw 'end') / to_raw_lua
        + (Ct(kw 'function' * Cg(V 'funcname', 'name') * space * V 'funcbody') / to_ast_func_named)
        + Ct(kw 'local' * kw 'function' * Cg(identword, 'name') * V 'funcbody') / as_local(to_ast_func_named)
        + Ct(kw 'local' * Cg(V 'namelist', 'lhs') * maybe(op '=' * Cg(V 'explist', 'rhs'))) / to_ast_assign_local
        + Ct(Cg(V 'varlist', 'lhs') * tkn '=' * Cg(V 'explist', 'rhs')) / to_ast_assign
        + C(V 'functioncall') / to_raw_lua,

    laststat = (kw "return" * maybe(V 'explist')) + kw "break",
    funcname = ident_name * maybe(identword),
    varlist = sep_by(space * V 'var', tkn ','),
    namelist = sep_by(identword, tkn ','),
    index = (tkn '[' * V 'expv' * tkn ']') + (P '.' * space * V 'name' * space * V 'args'),
    explist = sep_by(V 'expv', tkn ','),
    value = tkn 'nil'
        + C(tkn 'false') / to_raw_lua
        + C(tkn 'true') / to_raw_lua
        + C(number) / to_raw_lua
        + C(string_literal()) / to_raw_lua
        + C(tkn "...") / to_raw_lua
        + V 'function_'
        + C(V 'functioncall' * maybe(V 'vardot')) / to_raw_lua
        + (V 'var' * maybe(V 'vardot'))
        + V 'tableconstructor'
        + C(tkn '(' * V 'expv' * tkn ')') / to_raw_lua,
    space = space,
    exp = (V "unop" * V "space" * V "expv")
        + C(V 'value' * V 'space' * V 'binopright') / to_raw_lua,
    binopright = V 'binop' * V 'expv' * maybe(V 'binopright'),
    callprefix = (V 'tableindex' + ident_name),
    name = identword,
    suffix = V 'call' + V 'index',
    call = (V 'args') + (P ':' * space * V 'name' * space * V 'args'),
    functioncall_rec = V 'call' * maybe(V 'functioncall_rec'),
    functioncall = V 'callprefix' * V 'functioncall_rec',
    args = (tkn '(' * maybe(V 'explist') * tkn ')') + (V 'tableconstructor') + string_literal(),
    function_ = Ct(kw 'function' * V 'funcbody') / to_ast_func,
    funcbody = Cg(fn_args, 'args') * space * maybe(Cg(V 'block', 'body')) * kw 'end',
    parlist = (V 'namelist' * maybe(P "," * space * P '...')) + (P "..."),
    tableconstructor = Ct(tkn '{' * Cg(Ct(maybe(V 'fieldlist')), "fields") * tkn '}') / to_ast_tbl,
    fieldlist = sep_by(space * Cg(V 'field', 'fields') * space, V 'fieldsep') * maybe(V 'fieldsep'),
    fieldsep = tkn ',' + tkn ';',
    binop = binop(),
    tableindex = (V 'name' * ((tkn '.' * V 'name') ^ 1))
        + (ident_name * (tkn '[' * V 'expv' * tkn ']') ^ 1),
    expv = V 'exp' + V 'value',
    unop = P '~' + P 'not' + P '#',
    prefixexp = V 'var' + V 'functioncall' + (tkn '(' + V 'expv' + tkn ')'),
    vardot = tkn '.' * V 'var' * maybe(V 'vardot'),
    var = (C(V 'tableindex') / to_raw_lua) + V 'name',
    field = Ct(
        (tkn '[' * Cg(V 'expv', 'lhs') * tkn ']' * tkn '=' * Cg(V 'expv', 'rhs'))
        + (Cg(identword, 'lhs') * tkn '=' * Cg(V 'expv', 'rhs'))
        + (Cg(V 'expv', 'value'))) / to_ast_field,
}

function M.add_debug_trace(grammar)
    grammar = util.deep_copy(grammar)
    for k, p in pairs(grammar) do
        if k ~= 1 then
            local enter = lpeg.Cmt(lpeg.P(true), function(s, p, ...)
                print("ENTER: ", k)
                return p
            end);
            local leave = lpeg.Cmt(lpeg.P(true), function(s, p, ...)
                print("LEAVE: ", k)
                return p
            end) * (lpeg.P(p) - lpeg.P(p));
            grammar[k] = lpeg.Cmt(enter * p + leave, function(s, p, ...)
                print("--- " .. k .. " ---")
                print(p .. ":\n" .. s:sub(1, p - 1))
                return p
            end)
        end
    end
    return grammar
end

local rvalue = P {
    "rval",
    rval = ident_name + lua_function + lpeg.V "table",
    assign = assignment(lpeg.V "rval"),
    table = lua_table(lpeg.V "assign")
}
M.grammar = P(complete_grammer)
M.grammar_raw = complete_grammer

M.patterns = {
    string_literal = string_literal(),
    assignment = assignment(rvalue),
    lua_table = lua_table(assignment(rvalue)),
    rvalue = rvalue,
    variable_ns = ident_name,
    arglist = commasep_list,
    until_p = until_p,
    identchar = identchar,
    identword = identword,
    fn_args = fn_args,
    lua_function = lua_function,
    export_decl = (void(kw "export") * void(space) * lua_function) / function(c)
        return {
            type = types.EXPORT,
            target = c
        }
    end
}
function M.parse(code)
    local m = lpeg.match(Ct(M.grammar) * P(0), code)
    return m[1]
end

return M
