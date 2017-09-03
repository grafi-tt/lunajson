local error, setmetatable, tonumber, tostring =
      error, setmetatable, tonumber, tostring
local byte, char, find, gsub, match, sub =
      string.byte, string.char, string.find, string.gsub, string.match, string.sub
local floor, inf =
      math.floor, math.huge
local mininteger, tointeger =
      math.mininteger or nil, math.tointeger or nil

local _ENV = nil

local function newdecoder()
	local json, pos, nullv, arraylen

	-- `f` is the temporary for dispatcher[c] and
	-- the dummy for the first return value of `find`
	local dispatcher, f

	--[[
		Helper
	--]]
	local function decodeerror(errmsg)
		error("parse error at " .. pos .. ": " .. errmsg)
	end

	--[[
		Invalid
	--]]
	local function f_err()
		decodeerror('invalid value')
	end

	--[[
		Constants
	--]]
	-- null
	local function f_nul()
		if sub(json, pos, pos+2) == 'ull' then
			pos = pos+3
			return nullv
		end
		decodeerror('invalid value')
	end

	-- false
	local function f_fls()
		if sub(json, pos, pos+3) == 'alse' then
			pos = pos+4
			return false
		end
		decodeerror('invalid value')
	end

	-- true
	local function f_tru()
		if sub(json, pos, pos+2) == 'rue' then
			pos = pos+3
			return true
		end
		decodeerror('invalid value')
	end

	--[[
		Numbers
		Conceptually, the longest prefix that matches to `-?(0|[1-9][0-9]*)(\.[0-9]*)?([eE][+-]?[0-9]*)?`
		(in regexp) is captured as a number and its conformance to the JSON spec is checked.
	--]]
	-- deal with non-standard locales
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

	local function error_number()
		decodeerror('invalid number')
	end

	-- `0(\.[0-9]*)?([eE][+-]?[0-9]*)?`
	local function f_zro(mns)
		local postmp = pos
		local num
		local numret = 0
		local c = byte(json, postmp)
		if not c then
			return error_number()
		end

		if c == 0x2E then -- is this `.`?
			num = match(json, '^.[0-9]*', pos) -- skipping 0
			c = #num
			if c == 1 then
				return error_number()
			end
			postmp = pos + c
			c = byte(json, postmp)
		end

		if c == 0x45 or c == 0x65 then -- is this e or E?
			c = match(json, '^[^eE]*[eE][-+]?[0-9]+', pos)
			if not c then
				return error_number()
			end
			if num then
				num = c
			else -- `0e.*` is always 0.0
				numret = 0.0
			end
			postmp = pos + #c
		end

		pos = postmp
		if num then
			numret = fixedtonumber(num)
		end
		if mns then
			numret = -numret
		end
		return numret
	end

	-- `[1-9][0-9]*(\.[0-9]*)?([eE][+-]?[0-9]*)?`
	local function f_num(mns)
		pos = pos-1
		local num = match(json, '^.[0-9]*%.?[0-9]*', pos)
		if byte(num, -1) == 0x2E then
			return error_number()
		end
		local postmp = pos + #num
		local c = byte(json, postmp)

		if c == 0x45 or c == 0x65 then -- e or E?
			num = match(json, '^[^eE]*[eE][-+]?[0-9]+', pos)
			if not num then
				return error_number()
			end
			postmp = pos + #num
		end

		pos = postmp
		c = fixedtonumber(num)
		if mns then
			c = -c
			if c == mininteger then
				if not find(num, '[^0-9]') then
					c = mininteger
				end
			end
		end
		return c
	end

	-- skip minus sign
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

	--[[
		Strings
	--]]
	local f_str_hextbl = {
		0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9, inf, inf, inf, inf, inf, inf,
		inf, 0xA, 0xB, 0xC, 0xD, 0xE, 0xF, inf, inf, inf, inf, inf, inf, inf, inf, inf,
		inf, inf, inf, inf, inf, inf, inf, inf, inf, inf, inf, inf, inf, inf, inf, inf,
		inf, 0xA, 0xB, 0xC, 0xD, 0xE, 0xF, inf, inf, inf, inf, inf, inf, inf, inf, inf,
	}
	f_str_hextbl.__index = function()
		return inf
	end
	setmetatable(f_str_hextbl, f_str_hextbl)

	local f_str_escapetbl = {
		['"']  = '"',
		['\\'] = '\\',
		['/']  = '/',
		['b']  = '\b',
		['f']  = '\f',
		['n']  = '\n',
		['r']  = '\r',
		['t']  = '\t'
	}
	f_str_escapetbl.__index = function()
		decodeerror("invalid escape sequence")
	end
	setmetatable(f_str_escapetbl, f_str_escapetbl)

	local f_str_surrogate_prev = 0
	local function f_str_subst(ch, rest)
		-- 0.000003814697265625 = 2^-18
		-- 0.000244140625 = 2^-12
		-- 0.015625 = 2^-6
		local u8
		if ch == 'u' then
			local c1, c2, c3, c4 = byte(rest, 1, 4)
			local ucode = f_str_hextbl[c1-47] * 0x1000 +
			              f_str_hextbl[c2-47] * 0x100 +
			              f_str_hextbl[c3-47] * 0x10 +
			              f_str_hextbl[c4-47]
			if ucode == inf then
				myerror("invalid unicode charcode")
			end
			rest = sub(rest, 5)
			if ucode < 0x80 then -- 1byte
				u8 = char(ucode)
			elseif ucode < 0x800 then -- 2byte
				u8 = char(0xC0 + floor(ucode * 0.015625),
				          0x80 + ucode % 0x40)
			elseif ucode < 0xD800 or 0xE000 <= ucode then -- 3byte
				u8 = char(0xE0 + floor(ucode * 0.000244140625),
				          0x80 + floor(ucode * 0.015625) % 0x40,
				          0x80 + ucode % 0x40)
			elseif 0xD800 <= ucode and ucode < 0xDC00 then -- surrogate pair 1st
				if f_str_surrogate_prev == 0 then
					f_str_surrogate_prev = ucode
					if rest == '' then
						return ''
					end
				end
			else -- surrogate pair 2nd
				if f_str_surrogate_prev == 0 then
					f_str_surrogate_prev = 1
				else
					ucode = 0x10000 +
					        (f_str_surrogate_prev - 0xD800) * 0x400 +
					        (ucode - 0xDC00)
					f_str_surrogate_prev = 0
					u8 = char(0xF0 + floor(ucode * 0.000003814697265625),
					          0x80 + floor(ucode * 0.000244140625) % 0x40,
					          0x80 + floor(ucode * 0.015625) % 0x40,
					          0x80 + ucode % 0x40)
				end
			end
		end
		if f_str_surrogate_prev ~= 0 then
			f_str_surrogate_prev = 0
			decodeerror("invalid surrogate pair")
		end
		return (u8 or f_str_escapetbl[ch]) .. rest
	end

	-- caching interpreted keys for speed
	local f_str_keycache = setmetatable({}, {__mode="v"})

	local function f_str(iskey)
		local newpos = pos-2
		local pos2 = pos
		local c1, c2
		repeat
			newpos = find(json, '"', pos2, true) -- search '"'
			if not newpos then
				decodeerror("unterminated string")
			end
			pos2 = newpos+1
			while true do -- skip preceding '\\'s
				c1, c2 = byte(json, newpos-2, newpos-1)
				if c2 ~= 0x5C or c1 ~= 0x5C then
					break
				end
				newpos = newpos-2
			end
		until c2 ~= 0x5C -- check '"' is not preceded by '\'

		local str = sub(json, pos, pos2-2)
		pos = pos2

		if iskey then -- check key cache
			local str2 = f_str_keycache[str]
			if str2 then
				return str2
			end
		end
		local str2 = str
		if find(str2, '\\', 1, true) then -- check if backslash occurs
			str2 = gsub(str2, '\\(.)([^\\]*)', f_str_subst) -- interpret escapes
			if f_str_surrogate_prev ~= 0 then
				f_str_surrogate_prev = 0
				decodeerror("invalid surrogate pair")
			end
		end
		if iskey then -- commit key cache
			f_str_keycache[str] = str2
		end
		return str2
	end

	--[[
		Arrays, Objects
	--]]
	-- array
	local function f_ary()
		local ary = {}

		f, pos = find(json, '^[ \n\r\t]*', pos)
		pos = pos+1

		local i = 0
		if byte(json, pos) ~= 0x5D then -- check closing bracket ']', that consists an empty array
			local newpos = pos-1
			repeat
				i = i+1
				f = dispatcher[byte(json,newpos+1)] -- parse value
				pos = newpos+2
				ary[i] = f()
				f, newpos = find(json, '^[ \n\r\t]*,[ \n\r\t]*', pos) -- check comma
			until not newpos

			f, newpos = find(json, '^[ \n\r\t]*%]', pos) -- check closing bracket
			if not newpos then
				decodeerror("no closing bracket of an array")
			end
			pos = newpos
		end

		pos = pos+1
		if arraylen then -- commit the length of the array if `arraylen` is set
			ary[0] = i
		end
		return ary
	end

	-- objects
	local function f_obj()
		local obj = {}

		f, pos = find(json, '^[ \n\r\t]*', pos)
		pos = pos+1
		if byte(json, pos) ~= 0x7D then -- check the closing bracket '}', that consists an empty object
			local newpos = pos-1

			repeat
				pos = newpos+1
				if byte(json, pos) ~= 0x22 then -- check '"'
					decodeerror("not key")
				end
				pos = pos+1
				local key = f_str(true) -- parse key

				-- optimized for compact json
				-- c1, c2 == ':', <the first char of the value> or
				-- c1, c2, c3 == ':', ' ', <the first char of the value>
				f = f_err
				do
					local c1, c2, c3  = byte(json, pos, pos+3)
					if c1 == 0x3A then
						newpos = pos
						if c2 == 0x20 then
							newpos = newpos+1
							c2 = c3
						end
						f = dispatcher[c2]
					end
				end
				if f == f_err then -- read a colon and arbitrary number of spaces
					f, newpos = find(json, '^[ \n\r\t]*:[ \n\r\t]*', pos)
					if not newpos then
						decodeerror("no colon after a key")
					end
				end
				f = dispatcher[byte(json, newpos+1)] -- parse value
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

	--[[
		The jump table to dispatch a parser for a value, indexed by the code of the value's first char.
		Nil key means the end of json.
	--]]
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
	dispatcher.__index = function()
		decodeerror("unexpected termination")
	end
	setmetatable(dispatcher, dispatcher)

	--[[
		run decoder
	--]]
	local function decode(json_, pos_, nullv_, arraylen_)
		json, pos, nullv, arraylen = json_, pos_, nullv_, arraylen_

		pos = pos or 1
		f, pos = find(json, '^[ \n\r\t]*', pos)
		pos = pos+1

		f = dispatcher[byte(json, pos)]
		pos = pos+1
		local v = f()

		if pos_ then
			return v, pos
		else
			f, pos = find(json, '^[ \n\r\t]*', pos)
			if pos ~= #json then
				error('json ended')
			end
			return v
		end
	end

	return decode
end

return newdecoder
