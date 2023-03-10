# Sugarmoon
_Lua + nice stuff_

## Introduction

This is a lua transpiler for sugarmoon. Sugarmoon is a super-set of lua which
adds some basic syntactic sugar.

Be warned this is mostly a toy, I make no guarantees that it'll actually work
for more than basic examples.

## Extensions to Lua

### Lambdas

JS style lambda syntax

```sm
local f = x => x + 1
```
=>
```lua
local function f(x)
    return x + 1
end
```

### Brace-blocks

C family block syntax. Currently only supported for functions

```sm
local function f() {
    return 2
}
```
=>
```lua
local function f()
    return 2
end
```
