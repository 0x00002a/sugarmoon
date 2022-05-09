local util = require("src.util")


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
end)
