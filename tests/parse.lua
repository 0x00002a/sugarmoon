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

local function parse_gram(input)
    return parse_pat(parse.grammar, input).stmts[1]
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
        assert.are.same(ast.mk_fn_named('x'), rs[1].stmts[1])
    end)

    it("should parse a string literal", function()
        local input = 'x = "x"'
        local rs = parse_gram(input)
        assert.are.same(ast.mk_assign(ast.mk_name('x'), ast.mk_raw_lua('"x"')), rs)
    end)
    it("should parse assignment to a local function call", function()
        local input = "local x = y(2)"
        local rs = parse_gram(input)
        assert.are.same(ast.mk_local(ast.mk_assign(ast.mk_raw_word('x'),
            ast.mk_raw_lua("y(2)")
        )), rs)
    end)
    it("should parse assignment to a function call", function()
        local input = "x = y(2)"
        local rs = parse_gram(input)
        assert.are.same(ast.mk_assign(ast.mk_name('x'),
            ast.mk_raw_lua("y(2)")
        ), rs)
    end)
    it("should parse assignment to a function", function()
        local input = "x = function() end"
        local rs = parse_gram(input)
        assert.are.same(ast.mk_assign(ast.mk_name('x'),
            ast.mk_fn_annon()
        ), rs)
    end)

    it("should parse a function with table prefix and args", function()
        local input = [[
local x = y
local H = {}
function M.x(v)
    local v = 2
end
]]
        local rs = parse.parse(input).stmts[3]
        assert.are.same(ast.mk_fn_named('M.x', { 'v' }, ast.mk_chunk(ast.mk_local(ast.mk_assign(ast.mk_raw_word 'v', ast.mk_raw_lua '2')))), rs)
    end)

    it("should parse assignment with tables on both sides", function()
        local input = [[
t['x'] = f['y'] ]]
        local expected = ast.mk_assign(ast.mk_raw_lua("t['x'] "), ast.mk_raw_lua("f['y'] "))
        local actual = parse_gram(input)
        assert.are.same(expected, actual)

    end)
    it("should parse assignment with expr before", function()
        local input = [[
do
    local n
    t = x
end]]
        assert:set_parameter('TableFormatLevel', -1)
        local expected = ast.mk_block(
            ast.mk_chunk {
                ast.mk_local(ast.mk_assign(ast.mk_raw_word 'n', ast.mk_raw_lua('nil'))),
                ast.mk_assign(ast.mk_name 't', ast.mk_raw_word 'x')
            })
        local actual = parse_gram(input)
        assert.are.same(expected, actual)

    end)

    it("should parse for loop", function()
        local input = [[
for i = 1, #x do end]]
        local expected = ast.mk_raw_lua("for i = 1, #x do end")
        local actual = parse_gram(input)
        assert.are.same(expected, actual)

    end)
    it("should parse an if block", function()
        local input = [[
if x then y() end]]
        local expected = ast.mk_raw_lua("if x then y() end")
        local actual = parse_gram(input)
        assert.are.same(expected, actual)

    end)

    it("should parse an equality expression", function()
        local input = [[
do
    x = y == z end
        ]]
        assert:set_parameter('TableFormatLevel', -1)
        local expected = ast.mk_block(ast.mk_chunk {
            ast.mk_assign(ast.mk_name 'x', ast.mk_raw_lua 'y == z')
        }
        )
        local actual = parse_gram(input)
        assert.are.same(expected, actual)

    end)
    it("should parse a function return with args", function()
        local input = [[
function x(y)
    return function(z)
        x()end
end
        ]]
        assert:set_parameter('TableFormatLevel', -1)
        local expected = ast.mk_fn_named('x', { 'y' },
            ast.mk_chunk({},
                ast.mk_fn_annon({ 'z' },
                    ast.mk_chunk(
                        ast.mk_raw_lua("x()")
                    )
                )
            )
        )
        local actual = parse_gram(input)
        assert.are.same(expected, actual)

    end)

    it("should parse a table function call", function()
        local input = [[
h['y']()]]
        assert:set_parameter('TableFormatLevel', -1)
        local expected = ast.mk_raw_lua("h['y']()")
        local actual = parse_gram(input)
        assert.are.same(expected, actual)

    end)
    it("should parse a function return with statements", function()
        local input = [[
function x(y)
    local x = 2
    return h end
        ]]
        assert:set_parameter('TableFormatLevel', -1)
        local expected = ast.mk_fn_named('x', { 'y' },
            ast.mk_chunk({
                ast.mk_local(ast.mk_assign(
                    ast.mk_raw_word 'x',
                    ast.mk_raw_lua '2'))
            }, ast.mk_raw_word 'h')
        )
        local actual = parse_gram(input)
        assert.are.same(expected, actual)

    end)
    it("should parse a function return", function()
        local input = [[
function x()
    return function()
        x()end
end
        ]]
        assert:set_parameter('TableFormatLevel', -1)
        local expected = ast.mk_fn_named('x', {},
            ast.mk_chunk({},
                ast.mk_fn_annon({},
                    ast.mk_chunk(
                        ast.mk_raw_lua("x()")
                    )
                )
            )
        )
        local actual = parse_gram(input)
        assert.are.same(expected, actual)

    end)
    it("should parse table indexing", function()
        local input = [[
do
    local x = y[2]end
        ]]
        local rs = parse_gram(input).inner
        assert.are.same(ast.mk_chunk(
            {
            ast.mk_local(
                ast.mk_assign(
                    ast.mk_raw_word 'x',
                    ast.mk_raw_lua 'y[2]'
                )
            )
        }
        ), rs)
    end)
    it("should parse operators", function()
        local input = [[
do
    x = y ^ 2end
        ]]
        local rs = parse_gram(input).inner
        assert.are.same(ast.mk_chunk { ast.mk_assign(
            ast.mk_name 'x',
            ast.mk_raw_lua "y ^ 2")
        }, rs)
    end)
    it("should parse function with qualified call", function()
        local input = [[
local function x()
    local y = some.thing(2)end
        ]]
        local rs = parse_gram(input)
        assert.are.same(
            ast.mk_local(
                ast.mk_fn_named(ast.mk_raw_word 'x', {},
                    ast.mk_chunk {
                        ast.mk_local(
                            ast.mk_assign(
                                ast.mk_raw_word 'y',
                                ast.mk_raw_lua 'some.thing(2)'
                            )
                        )
                    }
                )
            )
            , rs)
    end)
    it("should parse a local function decl", function()
        local input = "local function x() end"
        local rs = parse_gram(input)
        assert.are.same(ast.mk_local(ast.mk_fn_named(ast.mk_raw_word 'x')), rs)
    end)
    it("should parse a function with table prefix", function()
        local input = "function M.x() end"
        local rs = parse_gram(input)
        assert.are.same(ast.mk_fn_named('M.x'), rs)
    end)
    it("should parse multiple functions", function()
        local input = "function x() end\nfunction y() end"
        local rs = parse.parse(input).stmts
        assert.are.same({
            ast.mk_fn_named('x'),
            ast.mk_fn_named('y')
        }, rs)
    end)
    it("should parse a lua function", function()
        local input = "function x(test,t2) end"
        local rs = parse_gram(input)
        assert.are.same(ast.mk_fn_named('x', { "test", "t2" }), rs)
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
            local rs = parse_gram(input)
            assert.are.same({
                type = types.ASSIGN,
                lhs = ast.mk_name('x'),
                rhs = ast.mk_raw_word('y'),
            }, rs)
        end)
    end)
    describe("lua table", function()
        it("should match", function()
            local input = "x = { t = {} }"
            local rs = parse_gram(input)
            assert.are.same(ast.mk_assign(ast.mk_name('x'), ast.mk_tbl({
                ['t'] = ast.mk_tbl({})
            }))
                , rs)
        end)
    end)
end)
