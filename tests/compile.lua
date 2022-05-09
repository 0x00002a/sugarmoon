local compile = require("src.compile")
local types = require("src.ast").types

local function compile_matches(expected)
    return function(ast)
        local output = compile.to_lua(ast)
        assert.are.same(expected, output)
    end
end

describe("compile tests", function()
    describe("compile normal lua", function()
        it("compiles a table", function()
            local tbl = {
                type = types.LUA_TABLE,
                values = {}
            }
            compile_matches("{}")(tbl)
        end)
    end)
    describe("compile sugarmoon", function()
        it("compiles export", function()
            local fname = "ftest"
            compile_matches("local __SmMod = {} function " .. fname .. "()end __SmMod." .. fname .. '=' .. fname) {
                type = types.EXPORT,
                target = {
                    type = types.LUA_FN,
                    args = {
                        type = types.ARG_LIST,
                        values = {},
                    }
                }
            }
        end)
    end)
end)
