local Bytecode = {}

--[[
	0 LOP_NOP 
	1 LOP_BREAK
	
	2 LOP_LOADNIL
	3 LOP_LOADB
	4 LOP_LOADN
	5 LOP_LOADK
	
	6 LOP_MOVE
	
	7 LOP_GETGLOBAL
	8 LOP_SETGLOBAL
	
	9 LOP_GETUPVAL
	10 LOP_SETUPVAL
	11 LOP_CLOSEUPVALS
	
	12 LOP_GETIMPORT
	
	13 LOP_GETTABLE
	14 LOP_SETTABLE
	
	15 LOP_GETTABLEKS
	16 LOP_SETTABLEKS
	
	17 LOP_GETTABLEN
	18 LOP_SETTABLEN
	
	19 LOP_NEWCLOSURE
	
	20 LOP_NAMECALL
	21 LOP_CALL
	
	22 LOP_RETURN
	
	23 LOP_JUMP
	24 LOP_JUMPBACK
	25 LOP_JUMPIF
	26 LOP_JUMPIFNOT
	27 LOP_JUMPIFEQ
	28 LOP_JUMPIFLE
	29 LOP_JUMPIFLT
	30 LOP_JUMPIFNOTEQ
	31 LOP_JUMPIFNOTLE
	32 LOP_JUMPIFNOTLT
	
	33 LOP_ADD
	34 LOP_SUB
	35 LOP_MUL
	36 LOP_DIV 
	37 LOP_MOD
	38 LOP_POW
	
	39 LOP_ADDK
	40 LOP_SUBK
	41 LOP_MULK
	42 LOP_DIVK
	43 LOP_MODK
	44 LOP_POWK
	
	45 LOP_AND
	46 LOP_OR
	
	47 LOP_ANDK
	48 LOP_ORK
	
	49 LOP_CONCAT

	50 LOP_NOT
	51 LOP_MINUS
	52 LOP_LENGTH
	
	53 LOP_NEWTABLE
	54 LOP_DUPTABLE
	
	55 LOP_SETLIST
	
	56 LOP_FORNPREP
	57 LOP_FORNLOOP
	
	58 LOP_FORGLOOP
	
	59 LOP_FORGPREP_INEXT
	60 LOP_FORGLOOP_INEXT
	
	61 LOP_FORGPREP_NEXT
	62 LOP_FORGLOOP_NEXT
	
	63 LOP_GETVARARGS
	
	64 LOP_DUPCLOSURE
	
	65 LOP_PREPVARARGS

	66 LOP_LOADKX
	
	67 LOP_JUMPX
	
	68 LOP_FASTCALL
	
	69 LOP_COVERAGE
	
	70 LOP_CAPTURE
	
	71 LOP_JUMPIFEQK
	72 LOP_JUMPIFNOTEQK
	
	73 LOP_FASTCALL1
	74 LOP_FASTCALL2
	75 LOP_FASTCALL2K
	
	76 LOP_FORGPREP
}]]

--[[
	N: unused
	K: constant
	U: used
	B: boolean
	F: built-in function ID
]]

--{FORMAT, ...ARGTYPE, AUX?}

Bytecode.Format = {
	[0] = {"ABC", "N", "N", "N"}, -- 0
	{"ABC", "N", "N", "N"}, -- 		 1
	{"ABC", "U", "N", "N"}, -- 		 2
	{"ABC", "U", "B", "U"}, -- 		 3
	{"AD", "U", "U"}, -- 			 4
	{"AD", "U", "K"}, -- 			 5
	{"ABC", "U", "U", "N"}, -- 		 6
	{"ABC", "U", "N", "N", "K"}, --  7
	{"ABC", "U", "N", "N", "K"}, --  8
	{"ABC", "U", "U", "N"}, -- 		 9
	{"ABC", "U", "U", "N"}, -- 		 10
	{"ABC", "U", "N", "N"}, -- 		 11
	{"AD", "U", "K", "U"}, -- 		 12
	{"ABC", "U", "U", "U"}, -- 		 13
	{"ABC", "U", "U", "U"}, -- 		 14
	{"ABC", "U", "U", "N", "K"}, --  15
	{"ABC", "U", "U", "N", "K"}, --  16
	{"ABC", "U", "U", "U"}, -- 		 17
	{"ABC", "U", "U", "U"}, -- 		 18
	{"AD", "U", "U"}, -- 			 19
	{"ABC", "U", "U", "N", "K"}, --  20
	{"ABC", "U", "U", "U"}, -- 		 21
	{"ABC", "U", "U", "N"}, -- 		 22
	{"AD", "N", "U"}, -- 			 23
	{"AD", "N", "U"}, -- 			 24
	{"AD", "U", "U"}, -- 			 25
	{"AD", "U", "U"}, -- 			 26
	{"AD", "U", "U", "U"}, -- 		 27
	{"AD", "U", "U", "U"}, -- 		 28
	{"AD", "U", "U", "U"}, -- 		 29
	{"AD", "U", "U", "U"}, -- 		 30
	{"AD", "U", "U", "U"}, -- 		 31
	{"AD", "U", "U", "U"}, -- 		 32
	{"ABC", "U", "U", "U"}, -- 		 33
	{"ABC", "U", "U", "U"}, -- 		 34
	{"ABC", "U", "U", "U"}, -- 		 35
	{"ABC", "U", "U", "U"}, -- 		 36
	{"ABC", "U", "U", "U"}, -- 		 37
	{"ABC", "U", "U", "U"}, -- 		 38
	{"ABC", "U", "U", "K"}, -- 		 39
	{"ABC", "U", "U", "K"}, -- 		 40
	{"ABC", "U", "U", "K"}, -- 		 41
	{"ABC", "U", "U", "K"}, -- 		 42
	{"ABC", "U", "U", "K"}, -- 		 43
	{"ABC", "U", "U", "K"}, -- 		 44
	{"ABC", "U", "U", "U"}, -- 		 45
	{"ABC", "U", "U", "U"}, -- 		 46
	{"ABC", "U", "U", "K"}, --		 47
	{"ABC", "U", "U", "K"}, -- 		 48
	{"ABC", "U", "U", "U"}, -- 		 49
	{"ABC", "U", "U", "N"}, -- 		 50
	{"ABC", "U", "U", "N"}, -- 		 51
	{"ABC", "U", "U", "N"}, -- 		 52
	{"ABC", "U", "N", "N", "U"}, --  53
	{"AD", "U", "K"}, -- 			 54
	{"ABC", "U", "U", "U", "U"}, --  55
	{"AD", "U", "U"}, -- 			 56
	{"AD", "U", "U"}, -- 			 57
	{"AD", "U", "U", "U"}, -- 		 58
	{"AD", "U", "U"}, -- 			 59
	{"AD", "U", "U"}, -- 			 60
	{"AD", "U", "U"}, -- 			 61
	{"AD", "U", "U"}, -- 			 62
	{"ABC", "U", "U", "N"}, -- 		 63
	{"AD", "U", "K"}, -- 			 64
	{"ABC", "U", "N", "N"}, -- 		 65
	{"ABC", "U", "N", "N", "K"}, --  66
	{"E", "U"}, -- 					 67
	{"ABC", "F", "N", "U"}, -- 		 68
	{"E", "U"}, -- 					 69
	{"ABC", "U", "U", "N"}, -- 		 70
	{"AD", "U", "U", "K"}, -- 		 71
	{"AD", "U", "U", "K"}, -- 		 72
	{"ABC", "F", "U", "U"}, -- 		 73
	{"ABC", "F", "U", "U", "U"}, --  74
	{"ABC", "F", "U", "U", "K"}, --  75
	{"AD", "U", "U"}, -- 			 76
}

--ARG = {OFFSET, SIZE, SIGNED?}

Bytecode.ArgOffsets = {
	A = {1, 1},
	B = {2, 1},
	C = {3, 1},
	D = {2, 2, true},
	E = {1, 3, true},
	Aux = {0, 4}
}

Bytecode.BTag = {
	LBC_VERSION = 2,
	
	LBC_CONSTANT_NIL = 0,
	LBC_CONSTANT_BOOLEAN = 1,
	LBC_CONSTANT_NUMBER = 2,
	LBC_CONSTANT_STRING = 3,
	LBC_CONSTANT_IMPORT = 4,
	LBC_CONSTANT_TABLE = 5,
	LBC_CONSTANT_CLOSURE = 6,
}

Bytecode.Fastcall = {
	assert,
	
	math.abs,
	math.acos,
	math.asin,
	math.atan2,
	math.atan,
	math.ceil,
	math.cosh,
	math.cos,
	math.deg,
	math.exp,
	math.floor,
	math.fmod,
	math.frexp,
	math.ldexp,
	math.log10,
	math.log,
	math.max,
	math.min,
	math.modf,
	math.pow,
	math.rad,
	math.sinh,
	math.sin,
	math.sqrt,
	math.tanh,
	math.tan,

	bit32.arshift,
	bit32.band,
	bit32.bnot,
	bit32.bor,
	bit32.bxor,
	bit32.btest,
	bit32.extract,
	bit32.lrotate,
	bit32.lshift,
	bit32.replace,
	bit32.rrotate,
	bit32.rshift,

	type,

	string.byte,
	string.char,
	string.len,

	typeof,

	string.sub,

	math.clamp,
	math.sign,
	math.round,

	rawset,
	rawget,
	rawequal,

	table.insert,
	table.unpack,

	Vector3.new,

	bit32.countlz,
	bit32.countrz,

	select
}

return Bytecode