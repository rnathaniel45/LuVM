local cfg = require "Config"
local Objects = {}

local CallInfo = {}; Objects.CallInfo = CallInfo
local Proto = {}; Objects.Proto = Proto
local Closure = {}; Objects.Closure = Closure
local Stack = {}; Objects.Stack = Stack

local csize, ssize = cfg.BASIC_CI_SIZE, cfg.BASIC_STACK_SIZE + cfg.EXTRA_STACK

--//Function prototype
function Proto.new()
	return {
		k = {},
		sizek = 0,
		code = {},
		sizecode = 0,
		p = {},
		sizep = 0,
		source = "",
		numparams = 0,
		is_vararg = false,
		maxstacksize = 0,
		nups = 0,
		linedefined = 0,
		debugname = ""
	}
end


--//Closure for proto
function Closure.new(p, nups, e)
	return {
		nupvalues = nups,
		stacksize = p.maxstacksize,
		p = p,
		uprefs = {},
		env = e,
		preload = false
	}
end

--//CallInfo for function
function CallInfo.new()
	return {
		base = 0,
		func = 0,
		top = 0,
		savedpc = 0,
		
		nresults = 0,
		flags = 0
	}
end

function Stack.new(L)
	L.stack = table.create(ssize)
end

--//New CallInfo Table
function CallInfo.newT(L)
	local base_ci = table.create(csize)
	base_ci[0] = CallInfo.new()
	
	L.base_ci = base_ci
end

return Objects
