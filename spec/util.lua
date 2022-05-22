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

    describe("rstrip", function()
        it("removes all trailing whitespace form a string", function()
            assert.are.same("x", util.rstrip("x     "))
        end)

        it("does not remove from the middle", function()
            assert.are.same("x  y", util.rstrip("x  y  "))
        end)
    end)
    describe("str_split", function()
        it("works with none of the seperator", function()
            assert.are.same({ "test" }, util.str_split("test", '.'))
        end)
    end)
end)
