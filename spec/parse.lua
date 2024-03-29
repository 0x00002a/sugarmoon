local parse = require("sugarmoon.parse")
local lpeg = require("lpeglabel")
local types = require("sugarmoon.ast").types
local ast = require("sugarmoon.ast")
local util = require("sugarmoon.util")

require("busted.runner")()

local function parse_pat(p, input)
    return parse.parse(input, lpeg.Ct(p))
end

local function strip_locations(ast)
    for k, v in pairs(ast) do
        if k == 'range' then
            ast[k] = nil
        elseif type(v) == 'table' then
            strip_locations(v)
        end
    end
    return ast
end

local function parse_gram(input, debug)
    if not debug then
        debug = false
    end
    local grammar = debug and parse.add_debug_trace(parse.grammar_raw) or parse.grammar
    local ok, err = parse_pat(lpeg.P(grammar), input)
    if ok then
        return strip_locations(ok[1].stmts[1])
    else
        return nil, err
    end
end

local function parse_raw(input)
    return parse.parse(input)
end

local function check_ast(input, ast, parse)
    if type(input) ~= 'table' then
        input = { input }
    end
    parse = parse or parse_gram
    for _, inp in pairs(input) do
        local out, err = parse(inp)
        assert.are.same(nil, err)
        strip_locations(out)
        assert.are.same(ast, out)
    end
end

local function mk_str(content, quotes)
    return ast.mk_string(content, { quotes, quotes })
end

describe("parser tests", function()
    it("should parse a language pragma", function()
        check_ast("#[[ language:lambdas ]]#", ast.mk_pragma("language:lambdas"))
    end)

    it("should require lambdas pragma for lambdas", function()
        local rs = parse.parse("local x = () => y")
        assert.are.same({ 'language:lambdas' }, rs.stmts[1].target.rhs.required_features)
    end)
    it("should parse a lua function with empty args", function()
        local input = "function x() end"
        local rs = lpeg.match(lpeg.Ct(parse.grammar), input)
        assert.are.same(ast.mk_fn_named('x'), parse_gram(input))
    end)

    it("should parse a string literal", function()
        local input = 'x = "x"'
        local rs = parse_gram(input)
        assert.are.same(ast.mk_assign(ast.mk_name('x'), ast.mk_string('x', { '"', '"' })), rs)
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
        local rs, e = parse.parse(input)
        assert.are.same(nil, e)
        rs = rs.stmts[3]
        strip_locations(rs)
        assert.are.same(ast.mk_fn_named('M.x', { 'v' },
            ast.mk_chunk(ast.mk_local(ast.mk_assign(ast.mk_raw_word 'v', ast.mk_raw_lua '2')))), rs)
    end)

    it("should parse assignment with tables on both sides", function()
        local input = [[
t['x'] = f['y'] ]]
        local expected = ast.mk_assign(ast.mk_raw_lua("t['x'] "), ast.mk_raw_lua("f['y'] "))
        local actual = parse_gram(input)
        assert.are.same(expected, actual)

    end)

    it("should parse a table and give all results", function()
        local input = [[
v = { 'a', 'b' }
        ]]
        assert:set_parameter('TableFormatLevel', -1)
        local expected = ast.mk_assign(ast.mk_name 'v',
            ast.mk_tbl {
                ast.mk_tbl_field(mk_str('a', "'")),
                ast.mk_tbl_field(mk_str('b', "'")),
            })
        local actual = parse_gram(input, false)
        assert.are.same(expected, actual)

    end)
    it("should parse an expression with elseif", function()
        local input = [[
if c.lhs then
    return y
elseif c then
    return x
end
        ]]
        assert:set_parameter('TableFormatLevel', -1)
        local expected = ast.mk_if_stmt(ast.mk_raw_lua 'c.lhs', ast.mk_chunk({}, ast.mk_raw_word 'y'), {
            {
                condition = ast.mk_raw_word 'c',
                body = ast.mk_chunk({}, ast.mk_raw_word 'x')
            }
        })
        local actual = parse_gram(input, false)
        assert.are.same(expected, actual)

    end)
    it("should parse an expression with dbls", function()
        local input = [[
v = "\\"
        ]]
        assert:set_parameter('TableFormatLevel', -1)
        local expected = ast.mk_assign(ast.mk_name 'v', ast.mk_string('\\\\', { '"', '"' }))
        local actual = parse_gram(input, false)
        assert.are.same(expected, actual)

    end)
    it("should parse a table with calls are fields", function()
        local input = [[
x = {
    f "y",
}
        ]]
        assert:set_parameter('TableFormatLevel', -1)
        local actual = parse_gram(input, false)
        assert.are.same(ast.mk_assign(ast.mk_name 'x',
            ast.mk_tbl {
                ast.mk_tbl_field(ast.mk_raw_lua('f "y"'))
            }
        ), actual)
    end)
    it("should parse a function with a table return", function()
        local input = [[
x(2, { y = 1 })
        ]]
        assert:set_parameter('TableFormatLevel', -1)
        local actual = parse_gram(input, false)
        assert.are.same(ast.mk_raw_lua(input), actual)
    end)
    it("should parse an expression with binop then unop constant", function()
        local input = [[
function m()
    return x ^ -1
end
        ]]
        assert:set_parameter('TableFormatLevel', -1)
        local actual = parse_gram(input, false)
        assert.is_true(actual.rhs.type == types.LUA_FN)
    end)

    it("should parse an expression with braces", function()
        local input = [[
local c = (y '' * f())]]
        assert:set_parameter('TableFormatLevel', -1)
        local expected = ast.mk_local(ast.mk_assign(ast.mk_raw_word 'c', ast.mk_raw_lua("(y '' * f())")))
        local actual = parse_gram(input, false)
        assert.are.same(expected, actual)

    end)
    it("should parse a call and then table deref", function()
        local input = [[
n = f(x).y
]]
        assert:set_parameter('TableFormatLevel', -1)
        local expected = ast.mk_assign(ast.mk_name 'n', ast.mk_raw_lua('f(x).y'))
        local actual = parse_gram(input, false)
        assert.are.same(expected, actual)

    end)

    it("should parse a call with table args", function()
        local input = [[
f(type(h)){ ['x'] = function() return y end }
]]
        assert:set_parameter('TableFormatLevel', -1)
        local expected = ast.mk_raw_lua(input)
        local actual = parse_gram(input, false)
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

    it("should parse a function with table colon", function()
        local input = [[
function f:x()
end
]]
        assert:set_parameter('TableFormatLevel', -1)
        local actual = parse_gram(input, false)
        assert.is_true(actual ~= nil)

    end)
    it("should parse a function with indent", function()
        local input = [[
function f()
    last_ids = ifdent > 3 or y
end

]]
        assert:set_parameter('TableFormatLevel', -1)
        local actual = parse_gram(input, false)
        assert.is_true(actual ~= nil)

    end)
    it("should parse a table with keys", function()
        local input = [[
v = {function()
            return '"' .. '"'
        end,
    }

]]
        assert:set_parameter('TableFormatLevel', -1)
        local actual = parse_gram(input, false)
        assert.is_true(actual ~= nil)

    end)
    it("should parse a function with params ...", function()
        local input = [[
function f(...) end
]]
        assert:set_parameter('TableFormatLevel', -1)
        local expected = ast.mk_fn_named('f', { "..." })
        local actual = parse_gram(input)
        assert.are.same(expected, actual)

    end)
    it("should parse a function call with ...", function()
        local input = [[
x(function(...) end)
]]
        assert:set_parameter('TableFormatLevel', -1)
        local expected = ast.mk_raw_lua(input)
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
        local rs = strip_locations(parse.parse(input).stmts)
        assert.are.same({
            ast.mk_fn_named('x'),
            ast.mk_fn_named('y')
        }, rs)
    end)

    it("should parse an if stmt", function()
        local input = "if x then return y end"
        check_ast(input, ast.mk_if_stmt(ast.mk_raw_word 'x', ast.mk_chunk({},
            ast.mk_raw_word 'y'), {}))
    end)
    it("should parse a lua function", function()
        local input = "function x(test,t2) end"
        local rs = parse_gram(input)
        assert.are.same(ast.mk_fn_named('x', { "test", "t2" }), rs)
    end)
    describe("function parse", function()
        it("with local function in body", function()
            local input = "function x() local function y() end local h = 5 return 3 end"
            assert.are.same(ast.mk_fn_named('x', {},
                ast.mk_chunk({ ast.mk_local(ast.mk_fn_named(ast.mk_raw_word 'y')),
                    ast.mk_local(ast.mk_assign(ast.mk_raw_word 'h', ast.mk_raw_lua '5')) }, ast.mk_raw_lua '3'))
                ,
                parse_gram(input))
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
                [ast.mk_raw_word 't'] = ast.mk_tbl({})
            }))
                , rs)
        end)
    end)
    describe("import extension", function()
        it("should parse an import decl", function()
            check_ast([[import "x.y"]], ast.mk_import('x.y'))
        end)
    end)
    describe("lambdas extension", function()
        it("should fail to parse a lambda with a chunk", function()
            local input = [[local f = x => do return y end]]
            assert.are.same(nil, lpeg.match(parse.grammar, input))
        end)

        it("should parse a lambda then call", function()
            local inputs = {
                [[
local f = () => 2
f()]]            ,
            }
            local expected = ast.mk_chunk {
                ast.mk_local(
                    ast.mk_assign(ast.mk_raw_word('f'), ast.add_requires_feat(
                        ast.mk_fn_annon({}, ast.mk_chunk({}, ast.mk_raw_lua '2')),
                        ast.lang_features.LAMBDAS))),
                ast.mk_raw_lua 'f()'
            }
            check_ast(inputs, expected, parse_raw)
        end)
        it("should parse a lambda inside an if", function()
            local inputs = {
                [[
if y then
    local f = x => y
end
                ]],
            }
            local expected = ast.mk_if_stmt(ast.mk_raw_word 'y', ast.mk_chunk { ast.mk_local(
                ast.mk_assign(ast.mk_raw_word('f'), ast.add_requires_feat(
                    ast.mk_fn_annon({ 'x' }, ast.mk_chunk({}, ast.mk_raw_word 'y')),
                    ast.lang_features.LAMBDAS))),
            }, {})
            check_ast(inputs, expected)
        end)
        it("should parse x => y end as a function with args x and body y", function()
            local inputs = {
                [[local f = x => return y end]],
                [[local f = (x) => return y end]],
                [[local f = x => y]],
                [[local f = (x) => y]],
            }
            local expected = ast.mk_local(
                ast.mk_assign(ast.mk_raw_word('f'), ast.add_requires_feat(
                    ast.mk_fn_annon({ 'x' }, ast.mk_chunk({}, ast.mk_raw_word 'y')),
                    ast.lang_features.LAMBDAS)))
            check_ast(inputs, expected)
        end)
    end)
end)
