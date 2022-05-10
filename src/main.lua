local compile = require("compile")
local parse = require("parse")
local util = require("util")


input = io.open(arg[1], "r")
content = input:read("*a")
input:close()
local ast = parse.parse(content)
local compiled = compile.to_lua(ast)

print(util.to_str(ast))
print("\n---\n")
print(compiled)
