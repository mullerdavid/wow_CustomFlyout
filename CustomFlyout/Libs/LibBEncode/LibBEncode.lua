--[[
	This is a library to encode decode a slightly modified version of BEncode to work with lua specifics. It has a normal (relaxed, lua specific) and a strict encode. Decode decodes both.

	Strict rules:
	An integer is encoded as i<integer encoded in base ten ASCII>e. Leading zeros are not allowed (although the number zero is still represented as "0"). Negative values are encoded by prefixing the number with a hyphen-minus. Negative zero is not permitted. 
	A byte string (a sequence of bytes, not necessarily characters) is encoded as <length>:<contents>. The length is encoded in base 10, like integers, but must be non-negative (zero is allowed); the contents are just the bytes that make up the string. 
	A list of values is encoded as l<contents>e . The contents consist of the bencoded elements of the list, in order, concatenated. Note the absence of separators between elements. Not implemented in encoding.
	A dictionary is encoded as d<contents>e. The elements of the dictionary are encoded with each key immediately followed by its value. 
	There are no restrictions on what kind of values may be stored in lists and dictionaries; they may (and usually do) contain other lists and dictionaries. This allows for arbitrarily complex data structures to be encoded.
	
	Relaxed extras:
	Integer can be float number as well (without exponent).
	In the dictionaries keys are relaxed, order is not important here, key can be other types.
	A boolean is encoded as b<1/0>e.
	
	
	Encode(bencode_input)
		This function is encoding the given input to a (relaxed) bencode string.
		Parameters:
			bencode_input: the input value or object
		Return:
			The encoded string.

	EncodeStrict(bencode_input)
		This function is encoding the given input to a (strict) bencode string.
		Parameters:
			bencode_input: the input value or object
		Return:
			The encoded string.

	Decode(bencode_input)
		This function is decoding the given bencode string input to the representation.
		Parameters:
			bencode_input: the encoded string
		Return:
			The decoded value or object.
		
	GetEncodeScript([inputname [, outputname] ])
		Generates a script that can be used in a secure wrapper. This is the functionality of Encode.
		Parameters:
			inputname: optional variable name for input, can't be RESERVED
			outputname: optional variable name for input, can't be RESERVED
		Return:
			The code as string to convert from inputname to outputname
		
	GetEncodeStrictScript([inputname [, outputname] ])
		Generates a script that can be used in a secure wrapper. This is the functionality of EncodeStrict.
		Parameters:
			inputname: optional variable name for input, can't be RESERVED
			outputname: optional variable name for input, can't be RESERVED
		Return:
			The code as string to convert from inputname to outputname
		
		
	GetDecodeScript([inputname [, outputname] ])
		Generates a script that can be used in a secure wrapper. This is the functionality of Decode.
		Parameters:
			inputname: optional variable name for input, can't be RESERVED
			outputname: optional variable name for input, can't be RESERVED
		Return:
			The code as string to convert from inputname to outputname
	
]]--

assert(LibStub, "LibBEncode requires LibStub")
local MAJOR, MINOR = "LibBEncode-1.0", 0;
local lib, oldminor = LibStub:NewLibrary(MAJOR, MINOR);
if not lib then return end

local encodeScript = [=[
	do
		local RESERVED = nil
		do
			local stack=newtable()
			local buffer=newtable()
			table.insert(stack, newtable(type(bencode_input), bencode_input))
			repeat
				local i = table.remove(stack, #stack)
				local t,v = i[1],i[2]
				if t=="number"
				then
					if -10000000000<v and v<10000000000
					then
						table.insert(buffer, "i"..v.."e")
					else
						v = tostring(v)
						table.insert(buffer, strlen(v)..":"..v)
					end
				elseif t=="boolean"
				then
					table.insert(buffer, "i"..(v and 1 or 0).."e")
				elseif t=="string"
				then
					table.insert(buffer, strlen(v)..":"..v)
				elseif t=="table"
				then
					table.insert(buffer, "d")
					table.insert(stack, newtable("end", nil))
					for tk, tv in pairs(v) 
					do
						table.insert(stack, newtable(type(tv), tv))
						table.insert(stack, newtable(type(tk), tk))
					end
				elseif t=="end"
				then
					table.insert(buffer, "e")
				else
					v = tostring(v)
					table.insert(buffer, strlen(v)..":"..v)
				end
			until #stack==0
			RESERVED = table.concat(buffer)
		end
		bencode_output = RESERVED
	end
]=]

local encodeStrictScript = [=[
	do
		local RESERVED = nil
		do
			local stack=newtable()
			local buffer=newtable()
			table.insert(stack, newtable(type(bencode_input), bencode_input))
			repeat
				local i = table.remove(stack, #stack)
				local t,v = i[1],i[2]
				if t=="number"
				then
					if -10000000000<v and v<10000000000 and v%1==0
					then
						table.insert(buffer, "i"..v.."e")
					else
						v = tostring(v)
						table.insert(buffer, strlen(v)..":"..v)
					end
				elseif t=="string"
				then
					table.insert(buffer, strlen(v)..":"..v)
				elseif t=="table"
				then
					table.insert(buffer, "d")
					table.insert(stack, newtable("end", nil))
					local keys = newtable()
					local map = newtable()
					for tk, _ in pairs(v) 
					do
						local stk = tostring(tk)
						table.insert(keys, stk)
						map[stk]=tk
					end
					for _, tk in ipairs(keys) 
					do
						local tv = v[map[tk]]
						table.insert(stack, newtable(type(tv), tv))
						table.insert(stack, newtable("string", tk))
					end
				elseif t=="end"
				then
					table.insert(buffer, "e")
				else
					v = tostring(v)
					table.insert(buffer, strlen(v)..":"..v)
				end
			until #stack==0
			RESERVED = table.concat(buffer)
		end
		bencode_output = RESERVED
	end
]=]

local decodeScript = [=[
	do
		local RESERVED = nil
		do
			local input = bencode_input
			local stack=newtable()
			local pos = 1
			local len = strlen(input)
			local state = newtable(false, nil) -- PUSH table.insert(stack, state) state = newtable(isdict, lastkey) -- POP state = table.remove(stack, #stack)
			repeat
				local symbol = strsub(input, pos, pos)
				local valuetype, value = true, nil
				if symbol == "i"
				then
					local _, e, v = strfind(input, "^(%-?%d+%.?%d*)e", pos+1)
					pos = e+1
					value = tonumber(v)
				elseif symbol == "b"
				then
					local v = strsub(input, pos+1, pos+1) == "1"
					pos = pos+3
					value = v
				elseif symbol == "l"
				then
					pos = pos+1
					valuetype = false
					table.insert(stack, state)
					state = newtable(false, nil)
					table.insert(stack, newtable())
				elseif symbol == "d"
				then
					pos = pos+1
					valuetype = false
					table.insert(stack, state)
					state = newtable(true, nil)
					table.insert(stack, newtable())
				elseif symbol == "e"
				then
					pos = pos+1
					value = table.remove(stack, #stack)
					state = table.remove(stack, #stack)
					state = newtable(state[1],state[2])
				else
					local start, e, len = strfind(input, "^(%d+):", pos)
					if len
					then
						len = tonumber(len)
						pos = e+1
						local v = strsub(input, pos, pos+len-1)
						value = v
						pos = pos+len
					else
						break
					end
				end
				if valuetype
				then
					if #stack>0
					then
						if state[1]
						then
							if state[2]
							then
								stack[#stack][state[2]]=value
								state[2] = nil
							else
								state[2] = value
							end
						else
							table.insert(stack[#stack], value)
						end
					else
						table.insert(stack, state)
						table.insert(stack, value)
					end
				end
			until pos>len
			RESERVED = stack[2]
		end
		bencode_output = RESERVED
	end
	
]=]

encodeFunc = loadstring("local bencode_output\n" .. encodeScript .. "\nreturn bencode_output")
encodeStrictFunc = loadstring("local bencode_output\n" .. encodeStrictScript .. "\nreturn bencode_output")
decodeFunc = loadstring("local bencode_output\n" .. decodeScript .. "\nreturn bencode_output")

local function newtable(...)
	return {...}
end

local function Encode(bencode_input)
	local func = encodeFunc
	local context = {bencode_input=bencode_input, newtable=newtable}
	setmetatable(context, { __index = _G})
	setfenv(func, context)
	return func()
end

local function EncodeStrict(bencode_input)
	local func = encodeStrictFunc
	local context = {bencode_input=bencode_input, newtable=newtable}
	setmetatable(context, { __index = _G})
	setfenv(func, context)
	return func()
end

local function Decode(bencode_input)
	local func = decodeFunc
	local context = {bencode_input=bencode_input, newtable=newtable}
	setmetatable(context, { __index = _G})
	setfenv(func, context)
	return func()
end

local function GetEncodeScript(inputname, outputname)
	local str = encodeScript
	if inputname and inputname ~= "RESERVED"
	then
		str = string.gsub(str, "bencode_input", inputname)
	end
	if outputname and outputname ~= "RESERVED"
	then
		str = string.gsub(str, "bencode_output", outputname)
	end
	return str
end

local function GetEncodeStrictScript(inputname, outputname)
	local str = encodeStrictScript
	if inputname and inputname ~= "RESERVED"
	then
		str = string.gsub(str, "bencode_input", inputname)
	end
	if outputname and outputname ~= "RESERVED"
	then
		str = string.gsub(str, "bencode_output", outputname)
	end
	return str
end

local function GetDecodeScript(inputname, outputname)
	local str = decodeScript
	if inputname and inputname ~= "RESERVED"
	then
		str = string.gsub(str, "bencode_input", inputname)
	end
	if outputname and outputname ~= "RESERVED"
	then
		str = string.gsub(str, "bencode_output", outputname)
	end
	return str
end

lib.Encode = Encode
lib.EncodeStrict = EncodeStrict
lib.Decode = Decode
lib.GetEncodeScript = GetEncodeScript
lib.GetEncodeStrictScript = GetEncodeStrictScript
lib.GetDecodeScript = GetDecodeScript

