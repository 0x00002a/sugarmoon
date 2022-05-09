local types = require("src.ast").types
local ast = require("src.ast")

describe("ast tests", function()
    describe("find_first", function()
        it("returns the first node with the given path if possible", function()
            local t = ast.mk_assign(ast.mk_name("x"), ast.mk_name("y"))
            assert.are.same(types.ASSIGN, ast.find_first({ types.ASSIGN }, t).type)
        end)
    end)
end)
