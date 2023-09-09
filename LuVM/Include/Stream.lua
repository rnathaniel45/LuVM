local Stream = {}
Stream.__index = Stream

function Stream:readBytes(amt)
	amt = amt or 1
	
	local old = self.Offset
	local newoff = old + amt
	
	self.Offset = newoff
	return string.byte(self.Data, old + 1, newoff)
end

function Stream:readInt32()
	local b1, b2, b3, b4 = self:readBytes(4)
	return b1 + b2 * 0x100 + b3 * 0x10000 + b4 * 0x1000000
end

function Stream:readString(size)
	local old = self.Offset
	
	self.Offset = self.Offset + size
	return size ~= 0 and string.sub(self.Data, old + 1, self.Offset) or ""
end

--Forked from FiOne by Rerumu
function Stream:readDouble()
	local b1, b2, b3, b4, b5, b6, b7, b8 = self:readBytes(8)
	
	local sign = (-1) ^ bit32.rshift(b8, 7)
	local exp = bit32.lshift(bit32.band(b8, 0x7F), 4) + bit32.rshift(b7, 4)
	local frac = bit32.band(b7, 0x0F) * 2 ^ 48
	local normal = 1

	frac = frac + (b6 * 2 ^ 40) + (b5 * 2 ^ 32) + (b4 * 2 ^ 24) + (b3 * 2 ^ 16) + (b2 * 2 ^ 8) + b1

	if exp == 0 then
		if frac == 0 then
			return sign * 0
		else
			normal = 0
			exp = 1
		end
	elseif exp == 0x7FF then
		if frac == 0 then
			return sign * (1 / 0)
		else
			return sign * (0 / 0)
		end
	end

	return sign * 2 ^ (exp - 1023) * (normal + frac / 2 ^ 52)
end

function Stream:readVarInt()
	local result = 0
	local shift = 0
	
	local byte
	
	repeat
		byte = self:readBytes()
		result = result + bit32.band(byte, 127) * 2 ^ shift
		
		shift = shift + 7
	until bit32.band(byte, 128) == 0
	
	return result
end

function Stream.new(data)
	return setmetatable({
		Data = data,
		Offset = 0
	}, Stream)
end

return Stream
