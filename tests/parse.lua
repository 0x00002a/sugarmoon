local parse = require("src.parse")
local lpeg = require("lpeg")

require("busted.runner")()


describe("parser tests", function()
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
        local input = "function (test) end"
        local rs = lpeg.match(lpeg.C(parse.patterns.lua_function), input)
        assert.same(input, rs)
    end)
end)

