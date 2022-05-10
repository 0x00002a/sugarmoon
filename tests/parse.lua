local parse = require("src.parse")
local lpeg = require("lpeg")
local types = require("ast").types
local ast = require("ast")
local util = require("util")

require("busted.runner")()

local pat = parse.patterns
local function parse_pat(p, input)
    return lpeg.match(lpeg.Ct(p), input)[1]
end

describe("parser tests", function()
    it("should parse function args with multiple commas", function()
        local input = "test,t2"
        local rs = lpeg.match(lpeg.C(parse.patterns.arglist), input)
        assert.same(input, rs)
    end)
    it("should parse function args", function()
        local input = "(test)"
        local rs = lpeg.match(lpeg.C(parse.patterns.fn_args), input)
        assert.same(input, rs)
    end)
    it("until_p should parse until expr", function()
        local input = "function x(test) end"
        local rs = lpeg.match(lpeg.C(parse.patterns.until_p(lpeg.P "end")), input)
        assert.same(input, rs)
    end)
    it("should parse a lua function with empty args", function()
        local input = "function x() end"
        local rs = lpeg.match(lpeg.Ct(parse.grammar), input)
        assert.are.same(ast.mk_fn_named('x'), rs[1])
    end)
    it("should parse a lua function", function()
        local input = "function x(test,t2) end"
        local rs = lpeg.match(lpeg.Ct(parse.grammar), input)
        assert.are.same(ast.mk_fn_named('x', { "test", "t2" }), rs[1])
    end)
    describe("export decl", function()
        it("should parse export function", function()
            local input = "export function x() end"
            local rs = lpeg.match(lpeg.Ct(parse.patterns.export_decl), input)[1]
            assert.are.same({
                type = types.EXPORT,
                target = ast.mk_fn_named('x', {}, " ")
            }, rs)

        end)
    end)
    describe("variable name", function()
        it("should match x", function()
            local input = "x"
            local rs = parse_pat(pat.variable_ns, input)
            assert.are.same(ast.mk_name('x'), rs)
        end)
    end)
    describe("assignment", function()
        it("should match x = y", function()
            local input = "x = y"
            local rs = lpeg.match(lpeg.Ct(parse.patterns.assignment), input)[1]
            assert.are.same({
                type = types.ASSIGN,
                lhs = ast.mk_name('x'),
                rhs = ast.mk_name('y'),
            }, rs)
        end)
    end)
    describe("lua table", function()
        it("should match", function()
            local input = "x = { t = {} }"
            local rs = lpeg.match(lpeg.Ct(parse.grammar), input)[1]
            assert.are.same(ast.mk_assign(ast.mk_name('x'), ast.mk_tbl({
                ['t'] = ast.mk_tbl({})
            }))
                , rs)
        end)
    end)
end)
