local compile = require("sugarmoon.compile")
local parse = require("sugarmoon.parse")
local util = require("sugarmoon.util")


local input = io.open(arg[1], "r")
local content = input:read("*a")
input:close()
local ast, err = parse.parse(content)
if err ~= nil then
    print("failed to parse input: " .. parse.render_err(err))
else
    local ok, compiled = pcall(compile.to_lua, ast)
    if not ok then
        ---@diagnostic disable-next-line: param-type-mismatch
        print("failed to compile: " .. compile.render_err(content, compiled))
    else
        print(compiled)
    end
end
