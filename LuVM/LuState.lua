local State = {}

local Objects = require "Include\\Obj"
local cfg = require "Include\\Config"

local CallInfo, Stack = Objects.CallInfo, Objects.Stack
local min = cfg.LUA_MINSTACK

--//New Lua State
function State.new()
	local L = {
		gt = {},
		openupval = {},
		ci = 0,
		top = 0,
		base = 0
	}

	CallInfo.newT(L)
	Stack.new(L)
	
	local ci = L.base_ci[0]
	
	ci.func = L.top
	ci.base = L.top + 1; L.base = ci.base
	ci.top = L.top + min; ci.flags = 1

	return L
end

return State
