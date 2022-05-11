local util = require("sugarmoon.util")


describe("util tests", function()
    describe("switch", function()
        it("calls the function at key", function()
            local rs = util.switch "v" {
                ['v'] = function()
                    return 2
                end
            }
            assert.are.same(2, rs)
        end)
    end)
    describe("str_split", function()
        it("works with none of the seperator", function()
            assert.are.same({ "test" }, util.str_split("test", '.'))
        end)
    end)
end)
