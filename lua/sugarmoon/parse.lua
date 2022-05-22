local lpeg = require("lpeglabel")
lpeg.locale(lpeg)

local util = require("sugarmoon.util")
local types = require("sugarmoon.ast").types
local ast = require("sugarmoon.ast")
local P = lpeg.P
local S = lpeg.S
local R = lpeg.R
local C = lpeg.C
local V = lpeg.V
local Ct = lpeg.Ct
local Cg = lpeg.Cg
local Cc = lpeg.Cc
local lbl = lpeg.T

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
    return space * (P(word) * -(lpeg.alnum + P '_')) * space
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
        if type(c[1]) == 'table' then
            for _, v in pairs(c[1].values) do
                table.insert(args, v.word)
            end
            if c[2] and c[2] ~= '' then
                table.insert(args, c[2])
            end
        else
            args = { c[1] }
        end
        return ast.mk_arglist(args)
    end

    local parlist = (commasep_list * C(maybe(tkn ',' * tkn '...'))) + C(tkn '...')

    local p = Ct((tkn '(' * maybe(parlist) * tkn ')')) / to_ast
    return p
end

local fn_args = mk_fn_args()

local function string_literal()

    local longstring = P { -- from Roberto Ierusalimschy's lpeg examples
        V "open" * C((P(1) - V "closeeq") ^ 0) *
            V "close" / function(o, s) return { content = s, quotes = { '[[', ']]' } } end;

        open = "[" * Cg((P "=") ^ 0, "init") * P "[" * (P "\n") ^ -1;
        close = "]" * C((P "=") ^ 0) * "]";
        closeeq = lpeg.Cmt(V "close" * lpeg.Cb "init", function(s, i, a, b) return a == b end)
    }
    local double = (P "\"" * C((P "\\" * P(1) + (1 - P "\"")) ^ 0) * P "\"") / function(s)
        return { content = s, quotes = { '"', '"' } }
    end
    local single = (P "'" * C((P "\\" * P(1) + (1 - P "'")) ^ 0) * P "'") / function(s)
        return { content = s, quotes = { "'", "'" } }
    end

    local m = double + single + longstring
    return m
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
        return ast.mk_tbl_field(c.lhs, c.rhs)
    elseif c.value then
        return ast.mk_tbl_field(c.value)
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
    return {
        type = types.LUA_TABLE,
        values = (c.fields == '' and {}) or c.fields
    }
end

local function single_arglist(values)
    return #values == 1 and values[1] or ast.mk_arglist(values)
end

local function to_ast_assign(c)
    local values = {}
    for _, v in pairs(c.lhs) do
        local name = (v.type == types.RAW_WORD and ast.mk_name(v.word)) or v
        table.insert(values, name)
    end
    return ast.mk_assign(single_arglist(values), single_arglist(c.rhs))
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
    retr = retr and single_arglist(retr)
    return ast.mk_chunk(stmts, retr)
end

local function to_ast_assign_local(c)
    local lhs = single_arglist(c.lhs)
    local rhs = single_arglist(c.rhs or { ast.mk_raw_lua('nil') })
    return ast.mk_local(ast.mk_assign(lhs, rhs))
end

local function as_local(inner)
    return function(c)
        return ast.mk_local(inner(c))
    end
end

local function to_ast_pragma(c)
    return ast.mk_pragma(util.rstrip(c))
end

local function to_ast_string(c)
    return ast.mk_string(c.content, c.quotes)
end

local hspace = lpeg.space ^ 0

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
            * ((kw 'elseif' * space * V 'expv' * kw 'then' * space * maybe(V 'block')) ^ 0)
            * maybe(kw 'else' * maybe(V 'block'))
            * kw 'end') / to_raw_lua
        + C(kw 'for' * space * V 'name' * op '=' * V 'expv' * tkn ',' * sep_by(V 'expv', tkn ',') * space * kw 'do' * maybe(V 'block') * kw 'end') / to_raw_lua
        + C(kw 'for' * V 'namelist' * kw 'in' * V 'explist' * kw 'do' * maybe(V 'block') * kw 'end') / to_raw_lua
        + (Ct(kw 'function' * Cg(V 'funcname', 'name') * space * V 'funcpostfix') / to_ast_func_named)
        + V 'local_fn'
        + V 'pragma'
        + Ct(kw 'local' * Cg(V 'namelist', 'lhs') * maybe(op '=' * Cg(V 'explist', 'rhs'))) / to_ast_assign_local
        + Ct(Cg(V 'varlist', 'lhs') * tkn '=' * Cg(V 'explist', 'rhs')) / to_ast_assign
        + C(V 'functioncall') / to_raw_lua,

    pragma = (P '#[[' * space * C((1 - P ']]#') ^ 0) * P ']]#') / to_ast_pragma,
    local_fn = Ct(kw 'local' * kw 'function' * Cg(V 'name', 'name') * V 'funcpostfix') / as_local(to_ast_func_named),
    keywords = kw 'and'
        + kw 'break'
        + kw 'do'
        + kw 'else'
        + kw 'elseif'
        + kw 'end'
        + kw 'false'
        + kw 'for'
        + kw 'function'
        + kw 'if'
        + kw 'in'
        + kw 'local'
        + kw 'nil'
        + kw 'not'
        + kw 'or'
        + kw 'repeat'
        + kw 'return'
        + kw 'then'
        + kw 'true'
        + kw 'until'
        + kw 'while',
    laststat = (kw "return" * maybe(V 'explist')) + kw "break",
    funcname = V 'identifier' * maybe(P ':' * V 'name'),
    varlist = Ct(sep_by(space * V 'var', tkn ',')),
    namelist = Ct(V 'name' * (void(tkn ',') * V 'name') ^ 0),
    index = (tkn '[' * V 'expv' * tkn ']') + (P '.' * space * V 'name' * space * V 'args'),
    explist = Ct(sep_by(V 'expv', tkn ',')),
    string_literal = string_literal() / to_ast_string,
    value = C(tkn 'nil') / to_raw_lua
        + C(tkn 'false') / to_raw_lua
        + C(tkn 'true') / to_raw_lua
        + C(number) / to_raw_lua
        + V 'string_literal'
        + C(tkn "...") / to_raw_lua
        + V 'function_'
        + C(V 'functioncall' * maybe(V 'vardot')) / to_raw_lua
        + V 'tableconstructor'
        + (V 'var' * maybe(V 'vardot'))
        + C(tkn '(' * V 'expv' * tkn ')') / to_raw_lua,
    space = space,
    exp = (V "unop" * V "space" * V "expv")
        + C(V 'value' * V 'space' * V 'binopright') / to_raw_lua,
    binopright = V 'binop' * V 'expv' * maybe(V 'binopright'),
    callprefix = (V 'tableindex' + V 'identifier'),
    name = identword - V 'keywords',
    suffix = V 'call' + V 'index',
    call = (V 'args') + (P ':' * hspace * V 'name' * hspace * V 'args'),
    functioncall_rec = V 'call' * maybe(V 'functioncall_rec'),
    functioncall = V 'callprefix' * V 'functioncall_rec',
    args = (hspace * P '(' * space * maybe(V 'explist') * tkn ')') + (space * V 'tableconstructor' * space) + (space * string_literal() * space),
    function_ = Ct(kw 'function' * V 'funcpostfix') / to_ast_func,
    funcparams = Cg(fn_args, 'args'),
    funcpostfix = V 'funcparams' * space * V 'funcbody',
    funcbody = maybe(Cg(V 'block', 'body')) * kw 'end',
    parlist = (V 'namelist' * maybe(P "," * space * P '...')) + (P "..."),
    tableconstructor = Ct(tkn '{' * Cg(maybe(V 'fieldlist'), "fields") * tkn '}') / to_ast_tbl,
    fieldlist = Ct(space / 0 * V 'field' * (space / 0 * V 'fieldsep' / 0 * space / 0 * V 'field') ^ 0) * maybe(V 'fieldsep'),
    fieldsep = tkn ',' + tkn ';',
    binop = binop(),
    identifier = ident_name - V 'keywords',
    tableindex = (V 'identifier' * (tkn '[' * V 'expv' * tkn ']') ^ 1)
        + (V 'name' * ((tkn '.' * V 'name') ^ 1)),
    expv = V 'exp' + V 'value',
    unop = P '-' + P 'not' + P '#',
    prefixexp = V 'var' + V 'functioncall' + (tkn '(' + V 'expv' + tkn ')'),
    vardot = tkn '.' * V 'var' * maybe(V 'vardot'),
    var = (C(V 'tableindex') / to_raw_lua) + V 'name',
    field = Ct(
        (tkn '[' * Cg(V 'expv', 'lhs') * tkn ']' * tkn '=' * Cg(V 'expv', 'rhs'))
        + (Cg(V 'name', 'lhs') * tkn '=' * Cg(V 'expv', 'rhs'))
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

local function as_export(p)
    return function(c)
        local inner = p(c)
        local name = inner.lhs.word
        return ast.mk_export({ name }, { ast.mk_local(inner) })
    end
end

local diag = {
    SmallLambdaInvalidStat = 'statement not allowed for lambda with implicit return',
}

local extensions = {
    lambdas = {
        function_ = function(before)
            local multiarg = Ct(V 'funcparams') / function(c)
                return c.args
            end
            local singlearg = Ct(V 'name') / function(c) return ast.mk_arglist({ c[1].word }) end
            local implicit_retr = (V 'stat' * lbl(diag.SmallLambdaInvalidStat)) + Ct(V 'expv') / function(c) return ast.mk_chunk({}, c[1]) end
            return before
                + Ct(Cg(multiarg + singlearg, 'args') * tkn '=>' * (V 'funcbody' + Cg(implicit_retr, 'body'))) / function(c)
                    return ast.add_requires_feat(to_ast_func(c), ast.lang_features.LAMBDAS)
                end
        end
    },
    import = {
        stat = function(before)
            local imp = (P 'import' * space * V 'string_literal') / function(c)
                return ast.mk_import(c.content)
            end
            return imp + before
        end,
    },
    implicit_return = {
        laststat = function(before)
            return before
                + (V 'expv')
        end
    }
}

local function apply_extension(patch, orig)
    local o = {}
    for k, v in pairs(orig) do
        if patch[k] then
            o[k] = patch[k](v)
        else
            o[k] = v
        end
    end
    return o
end

local function apply_extensions(orig)
    for _, v in pairs(extensions) do
        orig = apply_extension(v, orig)
    end
    return orig
end

complete_grammer = apply_extensions(complete_grammer)

M.grammar_raw = complete_grammer
M.grammar = P(complete_grammer)

function M.parse(code)
    local m, e, pos = lpeg.match(M.grammar * space * (-P(1) + lbl "didn't consume all input"), code)
    if not m then
        return m, { what = diag[e] or e, where = pos, remaining = code:sub(pos) }
    else
        return m
    end
end

return M
