local parse = require("parse")
local compile = require("compile")

describe("main tests", function()
    it("compiles basic test", function()
        local input = [[
x = { y = 2 }
        ]]
        local ast = parse.parse(input)
        local out = compile.to_lua(ast)
        assert.are.same(input, out)
    end)
end)
