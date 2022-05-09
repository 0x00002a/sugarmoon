local compile = require("src.compile")
local types = require("src.ast").types
local ast = require("src.ast")

local function compile_matches(expected)
    return function(ast)
        local ok, output = xpcall(function() return compile.to_lua(ast) end, function(e) print(debug.traceback(e)) end)
        assert.is_true(ok)
        assert.are.same(expected, output)
    end
end

describe("compile tests", function()
    describe("compile sugarmoon", function()
        it("compiles export", function()
            local fname = "ftest"
            compile_matches("local __SmModule={}\n" .. "local " .. fname .. "=function()end\n__SmModule." .. fname .. '=' .. fname) {
                type = types.EXPORT,
                target = ast.mk_local(ast.mk_fn_named(fname)),
            }
        end)
    end)
end)
