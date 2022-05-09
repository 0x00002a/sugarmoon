local lpeg = require("lpeg")
lpeg.locale(lpeg)

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

local function ast(name, pat)
    return pat / function(c)
        return {
            name = name,
            code = c
        }
    end
end

local function void(p)
    return p / 0
end

local open_brace = P "("
local close_brace = P ")"

local identchar = R("AZ", "az") + P "_"
local identword = identchar * ((identchar + R "09") ^ 0) / function(c) return { type = "identword", word = c } end
local commasep_list = Ct(identword * ((void(space * P "," * space) * identword) ^ 0))
    / function(c) return { type = "arg list", values = c } end
local fn_args = open_brace * commasep_list * close_brace
local until_p = function(p) return Cg((1 - p) ^ 0) * p end
local lua_function = Ct(
    void(P("function"))
    * void(space) * fn_args / 1 * until_p(P "end")) / function(c)
    return {
        type = "lua fn",
        args = c[1],
        body = c[2]
    }
end
M.patterns = {
    arglist = commasep_list,
    until_p = until_p,
    identchar = identchar,
    identword = identword,
    fn_args = fn_args,
    lua_function = lua_function,
    export_decl = C(kw "export" * lua_function)
}

return M
