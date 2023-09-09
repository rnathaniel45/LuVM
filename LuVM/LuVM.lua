local VM = {}

local Functions = require "Include\\Functions"
local Objects = require "Include\\Obj"

local pcall = pcall
local coroutine = coroutine
local debug = debug

local CallInfo = Objects.CallInfo
local Closure = Objects.Closure

--[[
STACK:
	MAIN FRAME:
	(0)	func CLOSURE
	(1)	func + 1 (base) ARGUMENTS...
]]

local function prepCall(L, func, cl, nparams, nresults, vg)
	local proto = cl.p

	local argtop = nparams == -1 and L.top or func + nparams
	local nci = CallInfo.new()
	
	nci.cl = cl
	nci.func = func
	nci.base = func + 1
	nci.top = argtop + cl.stacksize
	nci.nresults = nresults
	nci.vararg = vg

	L.ci = L.ci + 1
	L.base_ci[L.ci] = nci

	L.base = nci.base

	local argi = argtop
	local argend = L.base + proto.numparams

	while argi < argend do
		L.stack[argi] = nil
		argi = argi + 1
	end

	L.top = proto.is_vararg and argi or nci.top
end

local function findupval(L, level)
	local open = L.openupval
	local uv = open[level]
	
	if not uv then
		uv = {stack = L.stack, v = level}
		open[level] = uv
	end
	
	return uv
end

local function internalCall(L, func, cl, nresults, vg)
	prepCall(L, func, cl, -1, nresults, vg)
	return VM.executeState(L)
end

local function pushArg(L, push, base, cl)
	local tbp = cl.p.numparams
	
	table.move(push, 1, tbp, base, L.stack)
	L.top = base + tbp

	if cl.p.is_vararg then
		local vararg = {}
		vararg.n = tbp < push.n and push.n - tbp or 0
		
		table.move(push, tbp + 1, push.n, 0, vararg)
		return vararg
	end
end

function Functions.wrapClosure(L, cl)
	local wrapped
	wrapped = function(...)
		local orig = L.ithread
		local func = L.top
		
		assert(orig, "State is not active")

		local run = coroutine.running()
		local push = table.pack(...)

		if run ~= orig then --//Coroutine changed internally, make new thread
			local thread = Functions.newThread(L)
			thread.base_ci[0] = nil

			Functions.pushLClosure(thread, cl)
			local vg = pushArg(thread, push, 1, cl)

			return internalCall(thread, 0, cl, -1, vg)
		else --//No coroutine change, call interally and pop results
			L.stack[func] = wrapped
			local vg = pushArg(L, push, func + 1, cl)

			return internalCall(L, func, cl, -1, vg)
		end
	end
	
	return wrapped
end

local function doCall(L, func, nresults)
	local stack = L.stack
	local ccl = stack[func]
	
	local argtop = L.top - 1
	local args = {}

	--//Clean original stack before moving to top
	stack[func] = nil
	for i = func + 1, argtop do
		args[i - func] = stack[i]
		stack[i] = nil
	end

	local res = table.pack(ccl(unpack(args, 1, argtop - func)))
	local nr = res.n

	if nresults == -1 then
		L.top = func + nr
	else
		L.top = L.base_ci[L.ci].top
		nr = nresults
	end

	table.move(res, 1, nr, func, stack)
end

local function loopFORG(L, start, c)
	local stack = L.stack
	
	stack[start + 5] = stack[start + 2]
	stack[start + 4] = stack[start + 1]
	stack[start + 3] = stack[start]
	
	L.top = start + 6
	doCall(L, start + 3, c)
	L.top = L.base_ci[L.ci].top
	
	stack[start + 2] = stack[start + 3]
	return stack[start + 2] == nil
end

function VM.executeState(L)
	L.ithread = coroutine.running()
	
	local stack = L.stack

	local ci = L.base_ci[L.ci]
	local cl = ci.cl

	local k = cl.p.k
	local code = cl.p.code

	local base = L.base
	local pc = ci.savedpc
	
	local uprefs = cl.uprefs
	local openupval = L.openupval

	while true do
		local insn = code[pc]
		local op = insn[1]
		
		if op == 0 then
			pc = pc + 1
		elseif op == 1 then
			pc = pc + 1
		elseif op == 2 then
			pc = pc + 1
			stack[base + insn.A] = nil
		elseif op == 3 then
			pc = pc + 1
			stack[base + insn.A] = insn.B
			
			pc = pc + insn.C
		elseif op == 4 then
			pc = pc + 1
			stack[base + insn.A] = insn.D
		elseif op == 5 then
			pc = pc + 1
			local kv
			
			if insn.KD then
				kv = insn.D
			else
				kv = k[insn.D]
			end

			stack[base + insn.A] = kv
		elseif op == 6 then
			pc = pc + 1
			stack[base + insn.A] = stack[base + insn.B]
		elseif op == 7 then
			pc = pc + 2
			local kv
			
			if insn.KAux then
				kv = insn.Aux
			else
				kv = k[insn.Aux]
			end
			
			stack[base + insn.A] = cl.env[kv]
		elseif op == 8 then
			pc = pc + 2
			local kv

			if insn.KAux then
				kv = insn.Aux
			else
				kv = k[insn.Aux]
			end

			cl.env[kv] = stack[base + insn.A]
		elseif op == 9 then
			pc = pc + 1
			local uv = uprefs[insn.B]

			stack[base + insn.A] = uv.stack[uv.v]
		elseif op == 10 then
			pc = pc + 1
			local uv = uprefs[insn.B]

			uv.stack[uv.v] = stack[base + insn.A]
		elseif op == 11 then
			pc = pc + 1
			
			for level, uv in pairs(openupval) do
				if level >= insn.A then
					openupval[level] = nil
					
					uv.value = uv.stack[uv.v]
					uv.v = "value"
					uv.stack = uv
				end
			end
		elseif op == 12 then
			pc = pc + 2
			local kv
			
			if insn.KD then
				kv = insn.D
			else
				kv = k[insn.D]
			end
			
			if kv and L.safeenv then
				stack[base + insn.A] = kv
			else
				ci.savedpc = pc
				stack[base + insn.A] = Functions.resolveImport(L, cl.env, k, insn.Aux, false)
			end
		elseif op == 13 then
			pc = pc + 1
			stack[base + insn.A] = stack[base + insn.B][stack[base + insn.C]]
		elseif op == 14 then
			pc = pc + 1
			stack[base + insn.B][stack[base + insn.C]] = stack[base + insn.A]
		elseif op == 15 then
			pc = pc + 2
			local kv
			
			if insn.KAux then
				kv = insn.Aux
			else
				kv = k[insn.Aux]
			end
			
			stack[base + insn.A] = stack[base + insn.B][kv]
		elseif op == 16 then
			pc = pc + 2
			local kv

			if insn.KAux then
				kv = insn.Aux
			else
				kv = k[insn.Aux]
			end

			stack[base + insn.B][kv] = stack[base + insn.A]
		elseif op == 17 then
			pc = pc + 1
			stack[base + insn.A] = stack[base + insn.B][insn.C + 1]
		elseif op == 18 then
			pc = pc + 1
			stack[base + insn.B][insn.C + 1] = stack[base + insn.A]
		elseif op == 19 then
			pc = pc + 1
			
			local proto = cl.p.p[insn.D]
			local ncl = Closure.new(proto, proto.nups, cl.env)

			for i = 0, proto.nups - 1 do
				local uinsn = code[pc]
				pc = pc + 1
				
				assert(uinsn[1] == 70, "Missing LOP_CAPTURE")
				
				if uinsn.A == 0 then
					local uv = {v = "value", value = stack[base + uinsn.B]}
					uv.stack = uv
					
					ncl.uprefs[i] = uv
				elseif uinsn.A == 1 then
					ncl.uprefs[i] = findupval(L, base + uinsn.B)
				elseif uinsn.A == 2 then
					ncl.uprefs[i] = uprefs[uinsn.B]
				end
			end
			
			stack[base + insn.A] = Functions.wrapClosure(L, ncl)
			ci.savedpc = pc
		elseif op == 20 then
			pc = pc + 2
			local kv

			if insn.KAux then
				kv = insn.Aux
			else
				kv = k[insn.Aux]
			end
			
			local tab = stack[base + insn.B]
			
			stack[base + insn.A + 1] = tab
			stack[base + insn.A] = tab[kv]
		elseif op == 21 then
			pc = pc + 1
			
			local cfunc = base + insn.A
			local ccl = stack[cfunc]
			
			local nparams = insn.B - 1
			local nresults = insn.C - 1
			
			ci.savedpc = pc

			local argtop = nparams == -1 and L.top - 1 or cfunc + nparams
			local args = {}
			
			--//Clean original stack before moving to top
			stack[cfunc] = nil
			for i = cfunc + 1, argtop do
				args[i - cfunc] = stack[i]
				stack[i] = nil
			end

			local res = table.pack(ccl(unpack(args, 1, argtop - cfunc)))
			local nr = res.n

			if nresults == -1 then
				L.top = cfunc + nr
			else
				L.top = ci.top
				nr = nresults
			end

			table.move(res, 1, nr, cfunc, stack)
		elseif op == 22 then
			pc = pc + 1
			
			local nr = insn.B - 1
			local cip = L.base_ci[L.ci - 1]

			local vali = base + insn.A
			local valend = nr == -1 and L.top - 1 or vali + nr - 1
			
			L.ci = L.ci - 1
			L.base = cip and cip.base or base
			
			local rets = {}
			table.move(stack, vali, valend, 1, rets)
			
			--//Clean stack before returning
			for i = ci.func, ci.top do
				stack[i] = nil
			end

			return unpack(rets, 1, valend - vali + 1)
		elseif op == 23 then
			pc = pc + insn.D + 1
		elseif op == 24 then
			pc = pc + insn.D + 1
		elseif op == 25 then
			pc = pc + 1 + (stack[base + insn.A] and insn.D or 0)
		elseif op == 26 then
			pc = pc + 1 + (stack[base + insn.A] and 0 or insn.D)
		elseif op == 27 then
			pc = pc + 1 + (stack[base + insn.A] == stack[base + insn.Aux] and insn.D or 1)
		elseif op == 28 then
			pc = pc + 1 + (stack[base + insn.A] <= stack[base + insn.Aux] and insn.D or 1)
		elseif op == 29 then
			pc = pc + 1 + (stack[base + insn.A] < stack[base + insn.Aux] and insn.D or 1)
		elseif op == 30 then
			pc = pc + 1 + (stack[base + insn.A] == stack[base + insn.Aux] and 1 or insn.D)
		elseif op == 31 then
			pc = pc + 1 + (stack[base + insn.A] <= stack[base + insn.Aux] and 1 or insn.D)
		elseif op == 32 then
			pc = pc + 1 + (stack[base + insn.A] < stack[base + insn.Aux] and 1 or insn.D)
		elseif op == 33 then
			pc = pc + 1
			stack[base + insn.A] = stack[base + insn.B] + stack[base + insn.C]
		elseif op == 34 then
			pc = pc + 1
			stack[base + insn.A] = stack[base + insn.B] - stack[base + insn.C]
		elseif op == 35 then
			pc = pc + 1
			stack[base + insn.A] = stack[base + insn.B] * stack[base + insn.C]
		elseif op == 36 then
			pc = pc + 1
			stack[base + insn.A] = stack[base + insn.B] / stack[base + insn.C]
		elseif op == 37 then
			pc = pc + 1
			stack[base + insn.A] = stack[base + insn.B] % stack[base + insn.C]
		elseif op == 38 then
			pc = pc + 1
			stack[base + insn.A] = stack[base + insn.B] ^ stack[base + insn.C]
		elseif op == 39 then
			pc = pc + 1
			local kv
			
			if insn.KC then
				kv = insn.C
			else
				kv = k[insn.C]
			end
			
			stack[base + insn.A] = stack[base + insn.B] + kv
		elseif op == 40 then
			pc = pc + 1
			local kv

			if insn.KC then
				kv = insn.C
			else
				kv = k[insn.C]
			end

			stack[base + insn.A] = stack[base + insn.B] - kv
		elseif op == 41 then
			pc = pc + 1
			local kv

			if insn.KC then
				kv = insn.C
			else
				kv = k[insn.C]
			end

			stack[base + insn.A] = stack[base + insn.B] * kv	
		elseif op == 42 then
			pc = pc + 1
			local kv

			if insn.KC then
				kv = insn.C
			else
				kv = k[insn.C]
			end

			stack[base + insn.A] = stack[base + insn.B] / kv
		elseif op == 43 then
			pc = pc + 1
			local kv

			if insn.KC then
				kv = insn.C
			else
				kv = k[insn.C]
			end

			stack[base + insn.A] = stack[base + insn.B] % kv	
		elseif op == 44 then
			pc = pc + 1
			local kv

			if insn.KC then
				kv = insn.C
			else
				kv = k[insn.C]
			end

			stack[base + insn.A] = stack[base + insn.B] ^ kv
		elseif op == 45 then
			pc = pc + 1
			stack[base + insn.A] = stack[base + insn.B] and stack[base + insn.C]
		elseif op == 46 then
			pc = pc + 1
			stack[base + insn.A] = stack[base + insn.B] or stack[base + insn.C]
		elseif op == 47 then
			pc = pc + 1
			local kv

			if insn.KC then
				kv = insn.C
			else
				kv = k[insn.C]
			end
			
			stack[base + insn.A] = stack[base + insn.B] and kv
		elseif op == 48 then
			pc = pc + 1
			local kv

			if insn.KC then
				kv = insn.C
			else
				kv = k[insn.C]
			end

			stack[base + insn.A] = stack[base + insn.B] or kv
		elseif op == 49 then
			pc = pc + 1
			local str = ""
			
			for i = insn.B, insn.C do
				str = str .. stack[base + i]
			end
			
			stack[base + insn.A] = str
		elseif op == 50 then
			pc = pc + 1
			stack[base + insn.A] = not stack[base + insn.B]
		elseif op == 51 then
			pc = pc + 1
			stack[base + insn.A] = -stack[base + insn.B]
		elseif op == 52 then
			pc = pc + 1
			stack[base + insn.A] = #stack[base + insn.B]
		elseif op == 53 then
			pc = pc + 2
			stack[base + insn.A] = table.create(insn.Aux)
		elseif op == 54 then
			pc = pc + 1
			local kv
			
			if insn.KD then
				kv = insn.D
			else
				kv = k[insn.D]
			end
			
			stack[base + insn.A] = table.clone(kv)
		elseif op == 55 then
			pc = pc + 2
			
			local tab = stack[base + insn.A]
			local start = base + insn.B
			
			local count = insn.C - 1
			
			if count == -1 then
				count = L.top - insn.B
				L.top = ci.top
			end
			
			for i = 0, count - 1 do
				tab[i + insn.Aux] = stack[start + i]
			end
		elseif op == 56 then
			pc = pc + 1
			local start = base + insn.A
			
			local limit = assert(tonumber(stack[start]), "invalid 'for' limit value")
			local step = assert(tonumber(stack[start + 1]), "invalid 'for' step value")
			local idx = assert(tonumber(stack[start + 2]), "invalid 'for' initial value")
			
			stack[start] = limit
			stack[start + 1] = step
			stack[start + 2] = idx
			
			if step > 0 then
				pc = pc + (idx <= limit and 0 or insn.D)
			else
				pc = pc + (limit <= idx and 0 or insn.D)
			end
		elseif op == 57 then 
			pc = pc + 1
			local start = base + insn.A
			
			local limit = stack[start]
			local step = stack[start + 1]
			local idx = stack[start + 2] + step
			
			stack[start + 2] = idx

			if step > 0 then
				pc = pc + (idx <= limit and insn.D or 0)
			else
				pc = pc + (limit <= idx and insn.D or 0)
			end
		elseif op == 58 then
			pc = pc + 2
			local start = base + insn.A
			
			if not stack[start] then
				local tab = stack[start + 1]
				local idx = stack[start + 2]
				
				if insn.Aux > 2 then
					for i = 2, insn.Aux - 1 do
						stack[start + 3 + i] = nil
					end
				end

				local i = next(tab, idx)

				if i ~= nil then
					stack[start + 2] = i
					stack[start + 3] = i
					stack[start + 4] = tab[i]

					pc = pc + insn.D - 1
				end
			else
				stack[start + 5] = stack[start + 2]
				stack[start + 4] = stack[start + 1]
				stack[start + 3] = stack[start]
				
				L.top = L.top + 6
				
				doCall(L, start + 3, insn.Aux)
				L.top = ci.top
				
				stack[start + 2] = stack[start + 3]
				pc = pc + (stack[start + 2] == nil and 0 or (insn.D - 1))
			end
		elseif op == 59 then
			pc = pc + 1
			local start = base + insn.A
			
			if L.safeenv and type(stack[start + 1]) == "table" and stack[start + 2] == 0 then
				stack[start] = nil
			end
			
			pc = pc + insn.D
		elseif op == 60 then
			pc = pc + 1
			local start = base + insn.A
			
			if not stack[start] then
				local tab = stack[start + 1]
				local idx = stack[start + 2] + 1
				
				local v = tab[idx]
				
				if v ~= nil then
					stack[start + 2] = idx
					stack[start + 3] = idx
					stack[start + 4] = v
					
					pc = pc + insn.D
				end
			else
				local stop = loopFORG(L, start, 2)
				pc = pc + (stop and 0 or insn.D)
			end
		elseif op == 61 then
			pc = pc + 1
			local start = base + insn.A

			if L.safeenv and type(stack[start + 1]) == "table" and stack[start + 2] == nil then
				stack[start] = nil
			end

			pc = pc + insn.D
		elseif op == 62 then
			pc = pc + 1
			local start = base + insn.A

			if not stack[start] then
				local tab = stack[start + 1]
				local idx = stack[start + 2]

				local i = next(tab, idx)

				if i ~= nil then
					stack[start + 2] = i
					stack[start + 3] = i
					stack[start + 4] = tab[i]

					pc = pc + insn.D
				end
			else
				local stop = loopFORG(L, start, 2)
				pc = pc + (stop and 0 or insn.D)
			end
			
		elseif op == 63 then
			pc = pc + 1

			local b = insn.B - 1
			local vararg = ci.vararg
			
			local n = vararg.n
			local start = base + insn.A

			if b == -1 then
				for i = 0, n - 1 do
					stack[start + i] = vararg[i]
				end

				L.top = start + n
			else
				local i = 0 
				while i < b and i < n do
					stack[start + i] = vararg[i]
					i = i + 1
				end
				for i = n, b - 1 do
					stack[start + i] = nil
				end
			end
			
		elseif op == 64 then
			pc = pc + 1
			local kv
			
			if insn.KD then
				kv = insn.D
			else
				kv = k[insn.D]
			end
			
			local ncl = kv.env == cl.env and kv or Closure.new(kv.p, kv.nupvalues, cl.env)
			stack[base + insn.A] = Functions.wrapClosure(L, ncl)
			
			local i = 0
			while i < kv.nupvalues do
				local uinsn = code[pc + i]
				local uv
				
				assert(uinsn[1] == 70, "Missing LOP_CAPTURE")

				if uinsn.A == 0 then
					uv = {value = stack[base + uinsn.B], v = "value"}
					uv.stack = uv
				else
					uv = uprefs[uinsn.B]
				end
				
				local prev = ncl.uprefs[i]
				if ncl == kv and prev and rawequal(prev.stack[prev.v], uv.stack[uv.v]) then
					i = i + 1
					continue
				end
				
				if ncl == kv and not kv.preload then
					ncl = Closure.new(kv.p, kv.nupvalues, cl.env)
					stack[base + insn.A] = Functions.wrapClosure(L, ncl)
					
					i = 0
					continue
				end
				
				ncl.uprefs[i] = uv
				i = i + 1
			end

			ncl.preload = false
			pc = pc + kv.nupvalues
		elseif op == 65 then
			pc = pc + 1
			local nparams = insn.A
			
			local fixed = base
			base = L.top

			for i = 0, nparams - 1 do
				stack[base + i] = stack[fixed + i]
				stack[fixed + i] = nil
			end
			
			ci.base = base
			ci.top = base + cl.stacksize
			
			L.base = base
			L.top = ci.top
		elseif op == 66 then
			pc = pc + 2
			local kv
			
			if insn.KAux then
				kv = insn.Aux
			else
				kv = k[insn.Aux]
			end
			
			stack[base + insn.A] = kv
		elseif op == 67 then
			pc = pc + 1 + insn.E
		elseif op == 68 then
			pc = pc + 1
			
			local f = insn.A
			local skip = insn.C
			
			local call = code[pc + skip]
			
			local cfunc = base + call.A
			local nparams = call.B - 1
			local nresults = call.C - 1
			
			if L.safeenv and f then
				ci.savedpc = pc
				local argtop = nparams == -1 and L.top or cfunc + nparams

				local res = table.pack(f(unpack(stack, cfunc + 1, argtop)))
				local nr = res.n

				if nresults == -1 then
					L.top = cfunc + nr
				else
					L.top = ci.top
					nr = nresults
				end

				table.move(res, 1, nr, cfunc, stack)
				pc = pc + skip + 1
			end
		elseif op == 69 then
			pc = pc + 1
			
			local hits = insn.E
			insn.E = hits < 8388607 and hits + 1 or hits
		elseif op == 70 then
			error("LOP_CAPTURE should not be reachable")
		elseif op == 71 then
			pc = pc + 1
			local kv
			
			if insn.KAux then
				kv = insn.Aux
			else
				kv = k[insn.Aux]
			end
			
			pc = pc + (stack[base + insn.A] == kv and insn.D or 1)
		elseif op == 72 then
			pc = pc + 1
			local kv

			if insn.KAux then
				kv = insn.Aux
			else
				kv = k[insn.Aux]
			end

			pc = pc + (stack[base + insn.A] == kv and 1 or insn.D)
		elseif op == 73 then
			pc = pc + 1

			local f = insn.A
			local skip = insn.C

			local call = code[pc + skip]

			local cfunc = base + call.A
			local nresults = call.C - 1

			if L.safeenv and f then
				ci.savedpc = pc

				local res = table.pack(f(stack[base + insn.B]))
				local nr = res.n

				if nresults == -1 then
					L.top = cfunc + nr
				else
					L.top = ci.top
					nr = nresults
				end

				table.move(res, 1, nr, cfunc, stack)
				pc = pc + skip + 1
			end
		elseif op == 74 then
			pc = pc + 2

			local f = insn.A
			local skip = insn.C - 1

			local call = code[pc + skip]

			local cfunc = base + call.A
			local nresults = call.C - 1

			if L.safeenv and f then
				ci.savedpc = pc

				local res = table.pack(f(stack[base + insn.B], stack[base + insn.Aux]))
				local nr = res.n

				if nresults == -1 then
					L.top = cfunc + nr
				else
					L.top = ci.top
					nr = nresults
				end

				table.move(res, 1, nr, cfunc, stack)
				pc = pc + skip + 1
			end
		elseif op == 75 then
			pc = pc + 2
			local kv
			
			if insn.KAux then
				kv = insn.Aux
			else
				kv = k[insn.Aux]
			end

			local f = insn.A
			local skip = insn.C - 1

			local call = code[pc + skip]

			local cfunc = base + call.A
			local nresults = call.C - 1

			if L.safeenv and f then
				ci.savedpc = pc

				local res = table.pack(f(stack[base + insn.B], kv))
				local nr = res.n

				if nresults == -1 then
					L.top = cfunc + nr
				else
					L.top = ci.top
					nr = nresults
				end

				table.move(res, 1, nr, cfunc, stack)
				pc = pc + skip + 1
			end
		elseif op == 76 then
			pc = pc + 1 + insn.D
			
			local start = base + insn.A
			local gen = stack[start]
			
			local tgen = type(gen)
			
			if tgen == "table" or tgen == "userdata" then
				local mt = getmetatable(gen) --Does not handle metamethods correctly in the case of locked metatables: unavoidable without caching setmetatable
				mt = type(mt) == "table" and mt or false
				
				if mt then
					if type(mt.__iter) == "function" then
						stack[start + 1] = stack[start]
						stack[start] = mt.__iter
						
						L.top = start + 1
						doCall(L, start, 3)
						L.top = ci.top
					elseif type(mt.__call) == "function" then
						
					elseif tgen == "table" then
						stack[start + 1] = stack[start]
						
						stack[start] = nil
						stack[start + 2] = nil
					end
				elseif tgen == "table" then
					stack[start + 1] = stack[start]

					stack[start] = nil
					stack[start + 2] = nil
				end
			end
		else
			error("Bad opcode: " .. op)
		end
	end
end

return VM
