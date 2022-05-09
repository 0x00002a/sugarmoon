local parse = require("src.parse")
local lpeg = require("lpeg")

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
        local input = "function (test) end"
        local rs = lpeg.match(lpeg.C(parse.patterns.until_p(lpeg.P "end")), input)
        assert.same(input, rs)
    end)
    it("should parse a lua function with empty args", function()
        local input = "function () end"
        local rs = lpeg.match(lpeg.Ct(parse.patterns.lua_function), input)
        assert.are.same({
            type = "lua fn",
            body = " "
        }, rs[1])
    end)
    it("should parse a lua function", function()
        local input = "function (test,t2) end"
        local rs = lpeg.match(lpeg.Ct(parse.patterns.lua_function), input)
        assert.are.same({
            type = "lua fn",
            args = {
                type = "arg list",
                values = { {
                    type = "identword",
                    word = "test",
                },
                {
                    type = "identword",
                    word = "t2"
                }
                },
            },
            body = " "
        }, rs[1])
    end)
    describe("export decl", function()
        it("should parse export function", function()
            local input = "export function() end"
            local rs = lpeg.match(lpeg.Ct(parse.patterns.export_decl), input)[1]
            assert.are.same({
                type = "sm:export decl",
                target = {
                    type = "lua fn",
                    body = " "
                }
            }, rs)

        end)
    end)
    describe("variable name", function()
        it("should match x", function()
            local input = "x"
            local rs = parse_pat(pat.variable_ns, input)
            assert.are.same({
                type = 'ident:name',
                value = 'x'
            }, rs)
        end)
    end)
    describe("assignment", function()
        it("should match x = y", function()
            local input = "x = y"
            local rs = lpeg.match(lpeg.Ct(parse.patterns.assignment), input)[1]
            assert.are.same({
                type = 'expr:assign',
                lhs = {
                    type = 'ident:name',
                    value = 'x'
                },
                rhs = {
                    type = 'ident:name',
                    value = 'y'
                }
            }, rs)
        end)
    end)
    describe("lua table", function()
        it("should match", function()
            local input = "{ t = {} }"
            local rs = lpeg.match(lpeg.Ct(parse.patterns.lua_table), input)[1]
            assert.are.same({
                type = "lua:table",
                values = {
                    {
                        type = 'expr:assign',
                        lhs = {
                            type = 'ident:name',
                            value = 't'
                        },
                        rhs = {
                            type = 'lua:table',
                            values = {}
                        }
                    }
                }
            }, rs)
        end)
    end)
end)
