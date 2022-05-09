local lpeg = require("lpeg")
lpeg.locale(lpeg)

local ast = require("ast").types
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

local open_brace = P "("
local close_brace = P ")"

local identchar = R("AZ", "az") + P "_"
local identword = identchar * ((identchar + R "09") ^ 0) / function(c) return { type = ast.RAW_WORD, word = c } end
local commasep_list = Ct(identword * ((void(space * P "," * space) * identword) ^ 0))
    / function(c) return { type = ast.ARG_LIST, values = c } end
local fn_args = open_brace * commasep_list ^ -1 * close_brace
local until_p = function(p) return Cg((1 - p) ^ 0) * p end
local lua_function = Ct(
    void(kw("function"))
    * void(space) * fn_args / 1 * until_p(P "end")) / function(c)
    return {
        type = ast.LUA_FN,
        args = (type(c[1]) == 'table' and c[1]) or nil,
        body = c[2]
    }
end

local function op(ch)
    return P(ch)
end

local variable_ns = Ct(identword * (P '.' * identword) ^ 0) / function(c)
    local name = ""
    for _, n in pairs(c) do
        if type(n) == 'string' then
            name = name .. n
        else
            name = name .. n.word
        end
    end
    return {
        type = ast.IDENT_NAME,
        value = name
    }
end

local function lua_table(assignment)
    return Ct(void(P "{" * space) * (assignment ^ 0) * void(space * P "}"))
        / function(c)
            return {
                type = ast.LUA_TABLE,
                values = c
            }
        end
end

local function assignment(rvalue)
    return Ct(variable_ns * void(space * op "=" * space) * rvalue) / function(c)
        return {
            type = ast.ASSIGN,
            lhs = c[1],
            rhs = c[2]
        }
    end
end

local rvalue = P {
    "rval",
    rval = variable_ns + lua_function + lpeg.V "table",
    assign = assignment(lpeg.V "rval"),
    table = lua_table(lpeg.V "assign")
}

M.patterns = {
    assignment = assignment(rvalue),
    lua_table = lua_table(assignment(rvalue)),
    rvalue = rvalue,
    variable_ns = variable_ns,
    arglist = commasep_list,
    until_p = until_p,
    identchar = identchar,
    identword = identword,
    fn_args = fn_args,
    lua_function = lua_function,
    export_decl = (void(kw "export") * void(space) * lua_function) / function(c)
        return {
            type = "sm:export decl",
            target = c
        }
    end
}

return M
