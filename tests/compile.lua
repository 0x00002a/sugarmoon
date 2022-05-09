local compile = require("src.compile")
local types = require("src.ast").types

local function compile_matches(ast, expected)
    local output = compile.to_lua(ast)
    assert.are.same(expected, output)
end

describe("compile tests", function()
    describe("compile normal lua", function()
        it("compiles a table", function()
            local tbl = {
                type = types.LUA_TABLE,
                values = {}
            }
            compile_matches(tbl, "{}")
        end)
    end)

end)
