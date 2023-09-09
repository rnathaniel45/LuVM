# LuVM
In-Luau virtualized Luau Bytecode Virtual Machine

Based off of: https://github.com/Roblox/luau

Sample Code to run the VM:

```lua
local bytecode = [[Bytecode Data]]

local Loader = require "LuVM\\LuLoad"
local VM = require "LuVM\\LuVM"
local State = require "LuVM\\LuState"
local Functions = require "LuVM\\Include\\Functions"

local L = State.new()
L.gt = setmetatable({}, {__index = getfenv()})

Functions.sandboxState(L)

Loader.load(L, "string", bytecode, true)
print(VM.executeState(L))
```

Uses some functions and keywords that are not specific to vanilla lua:
```
continue
table.create
table.freeze
bit32
```
