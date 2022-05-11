local compile = require("sugarmoon.compile")
local parse = require("sugarmoon.parse")
local util = require("sugarmoon.util")


local input = io.open(arg[1], "r")
local content = input:read("*a")
input:close()
local ast = parse.parse(content)
local compiled = compile.to_lua(ast)

print(compiled)
