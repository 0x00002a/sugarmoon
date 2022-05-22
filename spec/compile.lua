local ast = require("sugarmoon.ast")
local compile = require("sugarmoon.compile")
local parse = require("sugarmoon.parse")
local util = require("sugarmoon.util")

describe("compile tests", function()
    describe("to_lua", function()
        it("parses a string back correctly", function()
            local nodes = parse.parse([["xy"]])
            print(util.to_str(nodes))

            assert.are.same([["xy"]], compile.to_lua(nodes))
        end)
    end)
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
