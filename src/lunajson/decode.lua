local floor = math.floor
local pow = math.pow
local byte = string.byte
local char = string.char
local find = string.find
local gsub = string.gsub
local len = string.len
local match = string.match
local sub = string.sub
local concat = table.concat
local tonumber = tonumber

local band, bor, rshift
if _VERSION == 'Lua 5.2' then
	band = bit32.band
	rshift = bit32.rshift
elseif type(bit) == 'table' then
	band = bit.band
	rshift = bit.rshift
else
	band = function(v, mask) -- mask must be 2^n-1
		return v % (mask+1)
	end
	rshift = function(v, len)
		return floor(v / pow(2, len))
	end
end

local function decode(json, pos, nullv)
	local _
	local jsonlen = len(json)
	local dodecode

	-- helper
	local function decodeerror(errmsg)
		error("parse error at " .. pos .. ": " .. errmsg)
	end

	-- parse constants
	local function f_nul()
		local str = sub(json, pos, pos+2)
		if str == 'ull' then
			pos = pos+3
			return nullv
		end
		decodeerror('invalid value')
	end

	local function f_fls()
		local str = sub(json, pos, pos+3)
		if str == 'alse' then
			pos = pos+4
			return false
		end
		decodeerror('invalid value')
	end

	local function f_tru()
		local str = sub(json, pos, pos+2)
		if str == 'rue' then
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
			return tonumber(gsub(s, radixmark, ''))
		end
	end

	local function cont_number(mns, newpos)
		local expc = byte(json, newpos+1)
		if expc == 0x45 or expc == 0x65 then -- e or E?
			_, newpos = find(json, '^[+-]?[0-9]+', newpos+2)
			if not newpos then
				decodeerror('invalid number')
			end
		end
		local num = fixedtonumber(sub(json, pos-1, newpos))
		if mns then
			num = -num
		end
		pos = newpos+1
		return num
	end

	local function f_zro(mns)
		local _, newpos = find(json, '^%.[0-9]+', pos)
		if newpos then
			return cont_number(mns, newpos)
		end
		return 0
	end

	local function f_num(mns)
		local _, newpos = find(json, '^[0-9]*%.?[0-9]*', pos)
		if byte(json, newpos) ~= 0x2E then -- check that num is not ended by comma
			return cont_number(mns, newpos)
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
	local f_str_surrogateprev

	local function f_str_subst(ch, rest)
		local u8
		if ch == 'u' then
			local l = len(rest)
			if l >= 4 then
				local ucode = tonumber(sub(rest, 1, 4), 16)
				rest = sub(rest, 5, l)
				if ucode < 0x80 then -- 1byte
					u8 = char(ucode)
				elseif ucode < 0x800 then -- 2byte
					u8 = char(0xC0 + rshift(ucode, 6), 0x80 + band(ucode, 0x3F))
				elseif ucode < 0xD800 or 0xE000 <= ucode then -- 3byte
					u8 = char(0xE0 + rshift(ucode, 12), 0x80 + band(rshift(ucode, 6), 0x3F), 0x80 + band(ucode, 0x3F))
				elseif 0xD800 <= ucode and ucode < 0xDC00 then -- surrogate pair 1st
					if f_str_surrogateprev == 0 then
						f_str_surrogateprev = ucode
						if l == 4 then
							return ''
						end
					end
				else -- surrogate pair 2nd
					if f_str_surrogateprev == 0 then
						f_str_surrogateprev = 1
					else
						ucode = 0x10000 + (f_str_surrogateprev - 0xD800) * 0x400 + (ucode - 0xDC00)
						f_str_surrogateprev = 0
						u8 = char(0xF0 + rshift(ucode, 18), 0x80 + band(rshift(ucode, 12), 0x3F), 0x80 + band(rshift(ucode, 6), 0x3F), 0x80 + band(ucode, 0x3F))
					end
				end
			end
		end
		if f_str_surrogateprev ~= 0 then
			decodeerror("invalid surrogate pair")
		end
		local tbl = {
			['"']  = '"',
			['\\'] = '\\',
			['/']  = '/',
			['b']  = '\b',
			['f']  = '\f',
			['n']  = '\n',
			['r']  = '\r',
			['t']  = '\t'
		}
		return (u8 or tbl[ch] or decodeerror("invalid escape sequence")) .. rest
	end

	local function f_str()
		local newpos = pos-2
		local pos2
		repeat
			pos2 = newpos+2
			newpos = find(json, '[\\"]', pos2)
			if not newpos then
				decodeerror("unterminated string")
			end
		until byte(json, newpos) == 0x22

		local str = sub(json, pos, newpos-1)
		if pos2 ~= pos then
			f_str_surrogateprev = 0
			str = gsub(str, '\\(.)([^\\]*)', f_str_subst)
		end

		pos = newpos+1
		return str
	end

	-- parse arrays
	local function f_ary()
		local ary = {}
		local i = 0

		_, pos = find(json, '^[ \n\r\t]*', pos)
		pos = pos+1
		if byte(json, pos) ~= 0x5D then
			local newpos = pos-1

			repeat
				i = i+1
				pos = newpos+1
				ary[i] = dodecode()
				_, newpos = find(json, '^[ \n\r\t]*,[ \n\r\t]*', pos)
			until not newpos

			_, newpos = find(json, '^[ \n\r\t]*%]', pos)
			if not newpos then
				return decodeerror("no closing bracket of an array")
			end
			pos = newpos
		end

		pos = pos+1
		return ary
	end

	-- parse objects
	local function f_obj()
		local obj = {}

		_, pos = find(json, '^[ \n\r\t]*', pos)
		pos = pos+1
		if byte(json, pos) ~= 0x7D then
			local newpos = pos-1

			repeat
				pos = newpos+1
				if byte(json, pos) ~= 0x22 then
					return decodeerror("not key")
				end
				pos = pos+1
				local key = f_str()
				_, newpos = find(json, '^[ \n\r\t]*:[ \n\r\t]*', pos)
				if not newpos then
					return decodeerror("no colon after a key")
				end
				pos = newpos+1
				obj[key] = dodecode()
				_, newpos = find(json, '^[ \n\r\t]*,[ \n\r\t]*', pos)
			until not newpos

			_, newpos = find(json, '^[ \n\r\t]*}', pos)
			if not newpos then
				return decodeerror("no closing bracket of an object")
			end
			pos = newpos
		end

		pos = pos+1
		return obj
	end

	local dispatcher = {
		false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
		false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
		false, false, f_str, false, false, false, false, false, false, false, false, false, false, f_mns, false, false,
		f_num, f_num, f_num, f_num, f_num, f_num, f_num, f_num, f_num, f_num, false, false, false, false, false, false,
		false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
		false, false, false, false, false, false, false, false, false, false, false, f_ary, false, false, false, false,
		false, false, false, false, false, false, f_fls, false, false, false, false, false, false, false, f_nul, false,
		false, false, false, false, f_tru, false, false, false, false, false, false, f_obj, false, false, false, false,
	}

	function dodecode()
		local c = byte(json, pos)
		if not c then
			decodeerror("unexpected termination")
		end
		local f = dispatcher[c+1]
		if not f then
			decodeerror("invalid value")
		end
		pos = pos+1
		return f()
	end

	_, pos = find(json, '^[ \n\r\t]*', pos)
	pos = pos+1
	local v = dodecode()
	return v, pos
end

return decode
