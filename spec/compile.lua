local ast = require("sugarmoon.ast")
local compile = require("sugarmoon.compile")
local parse = require("sugarmoon.parse")

describe("compile tests", function()
    describe("find_invalid_nodes", function()
        it("finds nodes with invalid language pragmas", function()
            local nodes = parse.parse([[
local y = () => x
            ]])
            assert.are.same(
                nodes.stmts[1].target.rhs,
                compile.find_invalid_nodes(nodes)[1].node)
        end)
    end)
end)
