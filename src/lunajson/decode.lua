local byte = string.byte
local char = string.char
local find = string.find
local gsub = string.gsub
local match = string.match
local sub = string.sub
local tonumber = tonumber

local genstrlib
if _VERSION == "Lua 5.3" then
	genstrlib = require 'lunajson._str_lib_lua53'
else
	genstrlib = require 'lunajson._str_lib'
end

local function decode(json, pos, nullv, arraylen)
	local dispatcher
	-- it is temporary for dispatcher[c] and
	-- dummy for 1st return value of find
	local f

	-- helper
	local function decodeerror(errmsg)
		error("parse error at " .. pos .. ": " .. errmsg)
	end

	-- parse error
	local function f_err()
		decodeerror('invalid value')
	end

	-- parse constants
	local function f_nul()
		if sub(json, pos, pos+2) == 'ull' then
			pos = pos+3
			return nullv
		end
		decodeerror('invalid value')
	end

	local function f_fls()
		if sub(json, pos, pos+3) == 'alse' then
			pos = pos+4
			return false
		end
		decodeerror('invalid value')
	end

	local function f_tru()
		if sub(json, pos, pos+2) == 'rue' then
			pos = pos+3
			return true
		end
		decodeerror('invalid value')
	end

	-- parse numbers
	local radixmark = match(tostring(0.5), '[^0-9]')
	local fixedtonumber = tonumber
	if radixmark ~= '.' then
		if find(radixmark, '%W') then
			radixmark = '%' .. radixmark
		end
		fixedtonumber = function(s)
			return tonumber(gsub(s, '.', radixmark))
		end
	end

	local function f_zro(mns)
		local c = byte(json, pos)
		if c == 0x2E then
			local num = match(json, '^.[0-9][-0-9.eE+]*', pos) -- skip 0
			if num then
				c = #num
				num = fixedtonumber(num)
				if num then
					pos = pos + c
					if mns then
						num = -num
					end
					return num
				end
			end
			decodeerror('invalid number')
		end
		if c == 0x45 or c == 0x65 then
			c = match(json, '^[^eE]*[eE][+-]?[0-9]+', pos)
			if not c then
				decodeerror('invalid number')
			end
			pos = pos + #c
		end
		if not mns then
			return 0.0
		end
		return -0.0
	end

	local function f_num(mns)
		pos = pos-1
		local num = match(json, '^[0-9]+%.?[0-9]*', pos)
		local c = byte(num, -1)
		if c ~= 0x2E then -- check that num is not ended by comma
			local pos2 = pos + #num
			c = byte(json, pos2)
			if c == 0x45 or c == 0x65 then -- e or E?
				num = match(json, '^[^eE]*[eE][+-]?[0-9]+', pos)
				if not num then
					decodeerror('invalid number')
				end
				pos2 = pos + #num
			end
			local num = fixedtonumber(num) - 0.0
			if mns then
				num = -num
			end
			pos = pos2
			return num
		end
		decodeerror('invalid number')
	end

	local function f_mns()
		local c = byte(json, pos)
		if c then
			pos = pos+1
			if c > 0x30 then
				if c < 0x3A then
					return f_num(true)
				end
			else
				if c > 0x2F then
					return f_zro(true)
				end
			end
		end
		decodeerror('invalid number')
	end

	-- parse strings
	local f_str_lib = genstrlib(decodeerror)
	local f_str_surrogateok = f_str_lib.surrogateok
	local f_str_subst = f_str_lib.subst

	local f_str_keycache = {}

	local function f_str(iskey)
		local newpos = pos-2
		local pos2 = pos
		local c1, c2
		repeat
			newpos = find(json, '"', pos2, true)
			if not newpos then
				decodeerror("unterminated string")
			end
			pos2 = newpos+1
			while true do
				c1, c2 = byte(json, newpos-2, newpos-1)
				if c2 ~= 0x5C or c1 ~= 0x5C then
					break
				end
				newpos = newpos-2
			end
		until c2 ~= 0x5C

		local str = sub(json, pos, pos2-2)
		pos = pos2

		if iskey then
			local str2 = f_str_keycache[str]
			if str2 then
				return str2
			end
		end
		local str2 = str
		if find(str2, '\\', 1, true) then
			str2 = gsub(str2, '\\(.)([^\\]*)', f_str_subst)
			if not f_str_surrogateok() then
				decodeerror("invalid surrogate pair")
			end
		end
		if iskey then
			f_str_keycache[str] = str2
		end
		return str2
	end

	-- parse arrays
	local function f_ary()
		local ary = {}

		f, pos = find(json, '^[ \n\r\t]*', pos)
		pos = pos+1

		local i = 0
		if byte(json, pos) ~= 0x5D then
			local newpos = pos-1
			repeat
				i = i+1
				f = dispatcher[byte(json,newpos+1)]
				pos = newpos+2
				ary[i] = f()
				f, newpos = find(json, '^[ \n\r\t]*,[ \n\r\t]*', pos)
			until not newpos

			f, newpos = find(json, '^[ \n\r\t]*%]', pos)
			if not newpos then
				decodeerror("no closing bracket of an array")
			end
			pos = newpos
		end

		pos = pos+1
		if arraylen then
			ary[0] = i
		end
		return ary
	end

	-- parse objects
	local function f_obj()
		local obj = {}

		f, pos = find(json, '^[ \n\r\t]*', pos)
		pos = pos+1
		if byte(json, pos) ~= 0x7D then
			local newpos = pos-1

			repeat
				pos = newpos+1
				if byte(json, pos) ~= 0x22 then
					decodeerror("not key")
				end
				pos = pos+1
				local key = f_str(true)
				f, newpos = find(json, '^[ \n\r\t]*:[ \n\r\t]*', pos)
				if not newpos then
					decodeerror("no colon after a key")
				end
				f = dispatcher[byte(json, newpos+1)]
				pos = newpos+2
				obj[key] = f()
				f, newpos = find(json, '^[ \n\r\t]*,[ \n\r\t]*', pos)
			until not newpos

			f, newpos = find(json, '^[ \n\r\t]*}', pos)
			if not newpos then
				decodeerror("no closing bracket of an object")
			end
			pos = newpos
		end

		pos = pos+1
		return obj
	end

	dispatcher = {
		       f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err,
		f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err,
		f_err, f_err, f_str, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_mns, f_err, f_err,
		f_zro, f_num, f_num, f_num, f_num, f_num, f_num, f_num, f_num, f_num, f_err, f_err, f_err, f_err, f_err, f_err,
		f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err,
		f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_ary, f_err, f_err, f_err, f_err,
		f_err, f_err, f_err, f_err, f_err, f_err, f_fls, f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_nul, f_err,
		f_err, f_err, f_err, f_err, f_tru, f_err, f_err, f_err, f_err, f_err, f_err, f_obj, f_err, f_err, f_err, f_err,
	}
	dispatcher[0] = f_err
	dispatcher.__index = function() -- byte is nil
		decodeerror("unexpected termination")
	end
	setmetatable(dispatcher, dispatcher)

	f, pos = find(json, '^[ \n\r\t]*', pos)
	pos = pos+1

	f = dispatcher[byte(json, pos)]
	pos = pos+1
	local v = f()
	return v, pos
end

return decode
