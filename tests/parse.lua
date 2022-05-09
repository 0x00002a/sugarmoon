local parse = require("src.parse")
local lpeg = require("lpeg")

require("busted.runner")()


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
        local input = "function (test) end"
        local rs = lpeg.match(lpeg.C(parse.patterns.until_p(lpeg.P "end")), input)
        assert.same(input, rs)
    end)
    it("should parse a lua function", function()
        local input = "function (test,t2) end"
        local rs = lpeg.match(lpeg.Ct(parse.patterns.lua_function), input)
        assert.are.same({
            type = "lua fn",
            args = {
                type = "arg list",
                values = { {
                    type = "identword",
                    word = "test",
                },
                {
                    type = "identword",
                    word = "t2"
                }
                },
            },
            body = " "
        }, rs[1])
    end)
end)
