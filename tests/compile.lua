local compile = require("src.compile")
local types = require("src.ast").types
local ast = require("src.ast")

local function compile_matches(expected)
    return function(ast)
        local output = compile.to_lua(ast)
        assert.are.same(expected, output)
    end
end

describe("compile tests", function()
    describe("compile sugarmoon", function()
        it("compiles export", function()
            local fname = "ftest"
            compile_matches("local __SmModule={}\nfunction " .. fname .. "()end\n__SmModule." .. fname .. '=' .. fname) {
                type = types.EXPORT,
                target = {
                    name = ast.mk_name(fname),
                    type = types.LUA_FN,
                    args = {
                        type = types.ARG_LIST,
                        values = {},
                    },
                    body = ''
                }
            }
        end)
    end)
end)
