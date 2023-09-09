local Functions = {}

local State = require "..\\LuState"

local function deepFreeze(tab, ignorefirst, blacklist)
	blacklist = blacklist or {}
	blacklist[tab] = true
	
	for i, v in pairs(tab) do
		if type(v) == "table" and not blacklist[v] then
			deepFreeze(v, false, blacklist)
		end
	end
	
	local suc, t = pcall(getmetatable, tab)
		
	if suc and type(t) == "table" and not blacklist[t] then
		deepFreeze(t, false, blacklist)
	end
	
	if not ignorefirst then
		pcall(table.freeze, tab)
	end
end

function Functions.pushStack(L, v)
	L.stack[L.top] = v
	L.top = L.top + 1
end

function Functions.popStack(L)
	local res = L.stack[L.top - 1]
	L.top = L.top - 1
	
	return res
end

function Functions.sandboxState(L)
	deepFreeze(L.gt, true)
	L.safeenv = true
end

function Functions.resolveImport(L, env, k, id, propogatenil)
	local count = bit32.rshift(id, 30)

	local id0 = count > 0 and bit32.band(bit32.rshift(id, 20), 1023) or -1
	local id1 = count > 1 and bit32.band(bit32.rshift(id, 10), 1023) or -1
	local id2 = count > 2 and bit32.band(id, 1023) or -1
	
	local topv = env[k[id0]]

	if id1 >= 0 and (not propogatenil or topv) then
		topv = topv[k[id1]]
	end

	if id2 >= 0 and (not propogatenil or topv) then
		topv = topv[k[id2]]
	end
	
	return topv
end

function Functions.newThread(L)
	local thread = State.new()
	
	local meta = {__index = L.gt}
	table.freeze(meta)
	
	thread.gt = setmetatable({}, meta)
	thread.safeenv = L.safeenv
	
	return thread
end

function Functions.pushLClosure(L, cl)
	Functions.pushStack(L, Functions.wrapClosure(L, cl))
end

return Functions