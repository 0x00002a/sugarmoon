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
local space = lpeg.space ^ 0
local Ct = lpeg.Ct
local Cg = lpeg.Cg

local M = {}


M.keywords = {}

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
    local name = ""
    for _, n in pairs(c) do
        if type(n) == 'string' then
            name = name .. n
        else
            name = name .. n.word
        end
    end
    return ast.mk_name(name)
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
local until_p = function(p) return Cg((1 - p) ^ 0) * p end

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

local function op(ch)
    return P(ch)
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

    local dbl = P '"' * valid_ch ^ 0 * P '"'
    local single = P "'" * valid_ch ^ 0 * P "'"
    local long = P "[[" * (valid_ch + P '\n') ^ 0 * P "]]"
    return dbl + single + long
end

local number = lpeg.digit ^ 1

local function binop()
    local ops = {
        '+', '-', '/', '*', '^', '%', '..', '<', '<=', '>', '>=', '==', '~=', 'and', 'or'
    }
    local out = nil
    for _, p in pairs(ops) do
        p = P(p)
        if not out then
            out = p
        else
            out = out + p
        end
    end
    return out
end

local function tkn(s)
    return space * P(s) * space
end

local function mk_chunk(p)
    local function to_ast(c)
        print(util.to_str(c))
    end

    local rs = Ct(p)
    return rs / to_ast
end

local complete_grammer = P {
    'chunk',
    chunk = mk_chunk(V "stat" + maybe(P ";") + maybe(V "laststat" + maybe(P ";"))),
    block = V "chunk",
    stat = (V 'varlist' * space * P '=' * space * V 'explist')
        + (V 'functioncall')
        + (kw 'do' * space * V 'block' * space * kw 'end')
        + (kw 'while' * space * V 'exp' * space * kw 'do' * space * V 'block' * space * kw 'end')
        + (kw 'repeat' * space * V 'block' * space * kw 'until' * space * V 'exp')
        + (kw 'if' * space * V 'exp' * space * kw 'then' * space * V 'block' * space
            * ((kw 'elseif' * space * kw 'then' * space * V 'block') ^ 0)
            * maybe(kw 'else' * V 'block')
            * kw 'end')
        + (kw 'for' * identword * op '=' * V 'exp' * tkn ',' * sep_by(V 'exp', tkn ',') * space * kw 'do' * V 'block' * kw 'end')
        + (kw 'for' * V 'namelist' * kw 'in' * V 'explist' * kw 'do' * V 'block' * kw 'end')
        + (kw 'function' * V 'funcname' * V 'funcbody')
        + (kw 'local' * kw 'function' * identword * V 'funcbody')
        + (kw 'local' * V 'namelist' * maybe(op '=' * V 'explist')),
    laststat = (P "return" * space * maybe(V 'explist')) + P "break",
    funcname = ident_name * maybe(identword),
    varlist = sep_by(V 'var', P ',' * space),
    namelist = sep_by(identword, P ',' * space),
    index = (tkn '[' * V 'exp' * tkn ']') + (P '.' * space * V 'name' * space * V 'args'),
    explist = ((V 'exp' * P ',' * space) ^ 0) * V 'exp',
    value = tkn 'nil'
        + tkn 'false'
        + tkn 'true'
        + number
        + string_literal()
        + tkn "..."
        + V 'function_'
        + V 'tableconstructor'
        + V 'var'
        + (tkn '(' * V 'exp' * tkn ')'),
    space = space,
    binopleft = (V 'binop' * space * V 'value') + P "",
    exp = V "unop" * V "space" * V "exp" +
        V 'binopleft' * (V "space" * V "binop" * V "space" * V "exp") ^ -1;
    --exp = (V 'unop' * V 'exp') + (V 'value' * maybe(space * V 'binop' * space * V 'exp')),
    prefix = (tkn '(' + V 'exp' + tkn ')') + V 'name',
    name = identword,
    suffix = V 'call' + V 'index',
    call = V 'args' + P ':' * space * V 'name' * space * V 'args',
    functioncall = V 'prefix' * (space * V 'suffix' * #(space * V 'suffix')) ^ 0 * space * V 'call',
    args = (tkn '(' * maybe(V 'explist') * tkn ')') + V 'tableconstructor' + string_literal(),
    function_ = P 'function' * V 'funcbody',
    funcbody = fn_args * V 'block' * P 'end',
    parlist = (V 'namelist' * maybe(P "," * space * P '...')) + (P "..."),
    tableconstructor = P '{' * V 'fieldlist' * P '}',
    fieldlist = sep_by(V 'field', V 'fieldsep') * maybe(V 'fieldsep'),
    fieldsep = P ',' + P ';',
    binop = binop(),
    unop = P '~' + P 'not' + P '#',
    var = (V 'prefix' * (space * V 'suffix' * #(space * V 'suffix')) ^ 0 * space * V 'index') + V 'name',
    field = (tkn '[' * V 'exp' * tkn ']' * tkn '=' * V 'exp') + (identword * tkn '=' * V 'exp') + V 'exp',
}

local rvalue = P {
    "rval",
    rval = ident_name + lua_function + lpeg.V "table",
    assign = assignment(lpeg.V "rval"),
    table = lua_table(lpeg.V "assign")
}
M.grammar = complete_grammer

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

return M
