local lpeg = require("lpeg")
lpeg.locale(lpeg)

local P = lpeg.P
local S = lpeg.S
local R = lpeg.R
local C = lpeg.C
local space = lpeg.space

local M = {}


M.keywords = {}

local function kw(word)
    M.keywords[word] = true
    return space * P (word)
end

local open_brace = P "("
local close_brace = P ")"

local identchar = R("AZ", "az") + P "_"
local identword = identchar * ((identchar + R "09") ^ 0)
local commasep_list = identword * ((space * P "," * space * identword) ^ 0)
local fn_args = open_brace * commasep_list * close_brace
local until_p = function(p) return ((1 - p)^0) * p end
local until_end = until_p(P "end")
local lua_function = P("function") * space * fn_args * space * until_p(until_end)
M.patterns = {
    until_p = until_p,
    identchar = identchar,
    identword = identword,
    fn_args = fn_args,
    lua_function = lua_function,
    export_decl = C(kw "export" * lua_function)
}

return M

