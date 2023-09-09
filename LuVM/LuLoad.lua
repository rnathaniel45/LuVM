local Loader = {}

local Objects = require "Include\\Obj"
local Bytecode = require "Include\\Bytecode"
local Stream = require "Include\\Stream"
local Functions = require "Include\\Functions"

local Proto = Objects.Proto
local Closure = Objects.Closure

local function resolveImportSafe(L, env, k, id)
	if L.safeenv then --//No getfenv or setfenv
		local status, res = pcall(Functions.resolveImport, L, env, k, id, true)

		if not status then
			warn("Failed to resolve an import in preload stage")
			return
		end
		
		return res
	end
end

local function readlString(bst, strings)
	local id = bst:readVarInt()
	return id ~= 0 and strings[id - 1] or nil
end

local function loadArg(insn, tab, format, k, typ)
	if format == "N" then
		return
	end
	
	local offsets = Bytecode.ArgOffsets[typ]
	local offset, size = offsets[1], offsets[2]
	
	local val0 = bit32.rshift(insn, offset * 8)
	local val
	
	if offsets[3] then
		val0 = bit32.band(val0, 256 ^ size - 1)
		val = val0 - bit32.band(val0, 2 ^ (size * 8 - 1)) * 2
	else
		val = bit32.band(val0, 256 ^ size - 1)
	end

	if format == "K" and k then
		val = k[val]
		tab["K" .. typ] = true --Indicate constant is resolved
	elseif format == "F" then
		val = Bytecode.Fastcall[val]
	elseif format == "B" then
		val = val ~= 0 and true or false
	end
	
	tab[typ] = val
end

function Loader.load(L, chunkname, data, cachec)
	local bst = Stream.new(data)
	local vers = bst:readBytes()

	if vers == 0 then
		error(string.format("%s: Bytecode error", chunkname))
	elseif vers ~= Bytecode.BTag.LBC_VERSION then
		error(string.format("%s: Expected bytecode version %s, got %s", chunkname, Bytecode.LBC_VERSION, vers))
	end

	local envt = L.gt

	local stringcount = bst:readVarInt()
	local strings = table.create(stringcount)

	for i = 0, stringcount - 1 do
		strings[i] = bst:readString(bst:readVarInt())
	end

	local protocount = bst:readVarInt()
	local protos = table.create(protocount)

	for i = 0, protocount - 1 do
		local proto = Proto.new()
		proto.source = chunkname

		proto.maxstacksize = bst:readBytes()
		proto.numparams = bst:readBytes()
		proto.nups = bst:readBytes()
		proto.is_vararg = bst:readBytes()

		proto.sizecode = bst:readVarInt()
		proto.code = table.create(proto.sizecode)

		local codestart = bst.Offset
		bst.Offset = codestart + proto.sizecode * 4

		proto.sizek = bst:readVarInt()
		proto.k = table.create(proto.sizek)

		for i = 0, proto.sizek - 1 do
			local tt = bst:readBytes()
			
			if tt == Bytecode.BTag.LBC_CONSTANT_NIL then
				proto.k[i] = nil
			elseif tt == Bytecode.BTag.LBC_CONSTANT_BOOLEAN then
				proto.k[i] = bst:readBytes() ~= 0
			elseif tt == Bytecode.BTag.LBC_CONSTANT_NUMBER then
				proto.k[i] = bst:readDouble()
			elseif tt == Bytecode.BTag.LBC_CONSTANT_STRING then
				proto.k[i] = readlString(bst, strings)
			elseif tt == Bytecode.BTag.LBC_CONSTANT_IMPORT then
				local iid = bst:readInt32()
				proto.k[i] = resolveImportSafe(L, envt, proto.k, iid)
			elseif tt == Bytecode.BTag.LBC_CONSTANT_TABLE then
				local keys = bst:readVarInt()
				local tab = table.create(keys)

				for i = 0, keys - 1 do
					local key = bst:readVarInt()
					tab[proto.k[key]] = 0
				end

				proto.k[i] = tab
			elseif tt == Bytecode.BTag.LBC_CONSTANT_CLOSURE then
				local fid = bst:readVarInt()
				local closure = Closure.new(protos[fid], protos[fid].nups, envt)

				closure.preload = closure.nupvalues > 0
				proto.k[i] = closure
			else
				error(string.format("Unknown constant type: %s", tt))
			end
		end
		
		local coffset = bst.Offset
		bst.Offset = codestart
		
		local code = proto.code
		
		local j = 0
		while j < proto.sizecode do
			local inst = bst:readInt32()
			
			local opcode = bit32.band(inst, 0xFF)
			local tab = {opcode}

			local format = Bytecode.Format[opcode]
			local kpass = cachec and proto.k or nil

			if format[1] == "ABC" then
				loadArg(inst, tab, format[2], kpass, "A")
				loadArg(inst, tab, format[3], kpass, "B")
				loadArg(inst, tab, format[4], kpass, "C")
				
				if format[5] and format[5] ~= "N" then
					local aux = bst:readInt32()
					loadArg(aux, tab, format[5], kpass, "Aux")
					
					code[j] = tab
					j = j + 2
					
					continue
				end
			elseif format[1] == "AD" then
				loadArg(inst, tab, format[2], kpass, "A")
				loadArg(inst, tab, format[3], kpass, "D")

				if format[4] and format[4] ~= "N" then
					local aux = bst:readInt32()
					loadArg(aux, tab, format[4], kpass, "Aux")
					
					code[j] = tab
					j = j + 2
					
					continue
				end
			elseif format[1] == "E" then
				loadArg(inst, tab, format[2], kpass, "E")

				if format[3] and format[3] ~= "N" then
					local aux = bst:readInt32()
					loadArg(aux, tab, format[3], kpass, "Aux")
					
					code[j] = tab
					j = j + 2
					
					continue
				end
			end
			
			code[j] = tab
			j = j + 1
		end

		bst.Offset = coffset

		proto.sizep = bst:readVarInt()
		proto.p = table.create(proto.sizep)

		for i = 0, proto.sizep - 1 do
			local fid = bst:readVarInt()
			proto.p[i] = protos[fid]
		end
		
		proto.linedefined = bst:readVarInt()
		proto.debugname = readlString(bst, strings)
		
		local lineinfo = bst:readBytes()

		if lineinfo ~= 0 then
			proto.linegaplog2 = bst:readBytes()

			local intervals = bit32.rshift(proto.sizecode - 1, proto.linegaplog2) + 1
			local absoffset = bit32.band(proto.sizecode + 3, -4)
	
			proto.sizelineinfo = absoffset + intervals --* 4 --(Omitted cus we are not working with a 1 byte array)
			proto.lineinfo = table.create(proto.sizelineinfo)
			proto.abslineinfo = absoffset

			local lastoffset = 0
			for i = 0, proto.sizecode - 1 do
				lastoffset = lastoffset + bst:readBytes()
				proto.lineinfo[i] = lastoffset
			end

			local lastline = 0
			for i = 0, intervals - 1 do
				lastline = lastline + bst:readInt32()
				proto.lineinfo[i + absoffset] = lastline
			end
		end

		local debuginfo = bst:readBytes()

		if debuginfo ~= 0 then
			proto.sizelocvars = bst:readVarInt()
			proto.locvars = table.create(proto.sizelocvars)
			
			for i = 0, proto.sizelocvars - 1 do
				local locvar = {}
				proto.locvars[i] = locvar
				
				locvar.varname = readlString(bst, strings)
				locvar.startpc = bst:readVarInt()
				locvar.endpc = bst:readVarInt()
				locvar.reg = bst:readBytes()
			end
			
			proto.sizeupvalues = bst:readVarInt()
			proto.upvalues = table.create(proto.sizeupvalues)
			
			for i = 0, proto.sizeupvalues - 1 do
				proto.upvalues[i] = readlString(bst, strings)
			end
		end

		protos[i] = proto
	end

	local main = protos[bst:readVarInt()]
	local cl = Closure.new(main, 0, envt)
	
	Functions.pushLClosure(L, cl)
	L.base_ci[0].cl = cl
end

return Loader