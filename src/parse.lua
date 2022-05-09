local lpeg = require("lpeg")
lpeg.locale(lpeg)

local util = require("util")
local types = require("ast").types
local ast = require("ast")
local P = lpeg.P
local S = lpeg.S
local R = lpeg.R
local C = lpeg.C
local space = lpeg.space ^ 0
local Ct = lpeg.Ct
local Cg = lpeg.Cg

local M = {}


M.keywords = {}

local function kw(word)
    M.keywords[word] = true
    return space * P(word)
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

local rvalue = P {
    "rval",
    rval = ident_name + lua_function + lpeg.V "table",
    assign = assignment(lpeg.V "rval"),
    table = lua_table(lpeg.V "assign")
}

M.patterns = {
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
