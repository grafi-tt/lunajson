local error, setmetatable, tonumber, tostring =
      error, setmetatable, tonumber, tostring
local floor, inf =
      math.floor, math.huge
local mininteger, tointeger =
      math.mininteger or nil, math.tointeger or nil
local byte, char, find, gsub, match, sub =
      string.byte, string.char, string.find, string.gsub, string.match, string.sub

local f_str_ctrl_pat
if _VERSION == "Lua 5.1" then
	-- use the cluttered pattern because lua 5.1 does not handle \0 in a pattern correctly
	f_str_ctrl_pat = '[^\32-\255]'
else
	f_str_ctrl_pat = '[\0-\31]'
end

local _ENV = nil


local function newdecoder()
	local json, pos, nullv, arraylen, newobj

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
		Conceptually, the longest prefix that matches to
		`-?(0|[1-9][0-9]*)(\.[0-9]*)?([eE][+-]?[0-9]*)?` (in regexp) is
		captured as a number and its conformance to the JSON spec is checked.
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
			return 0
		end

		if c == 0x2E then  -- is this `.`?
			num = match(json, '^.[0-9]*', pos)  -- skipping 0
			c = #num
			if c == 1 then
				return error_number()
			end
			postmp = pos + c
			c = byte(json, postmp)
		end

		if c == 0x45 or c == 0x65 then  -- is this e or E?
			c = match(json, '^[^eE]*[eE][-+]?[0-9]+', pos)
			if not c then
				return error_number()
			end
			if num then
				num = c
			else  -- `0e.*` is always 0.0
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
		if byte(num, -1) == 0x2E then  -- `.`?
			return error_number()
		end
		local postmp = pos + #num
		local c = byte(json, postmp)

		if c == 0x45 or c == 0x65 then  -- e or E?
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
		0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7,
		0x8, 0x9, inf, inf, inf, inf, inf, inf,
		inf, 0xA, 0xB, 0xC, 0xD, 0xE, 0xF, inf,
		inf, inf, inf, inf, inf, inf, inf, inf,
		inf, inf, inf, inf, inf, inf, inf, inf,
		inf, inf, inf, inf, inf, inf, inf, inf,
		inf, 0xA, 0xB, 0xC, 0xD, 0xE, 0xF,
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
		['t']  = '\t',
	}
	f_str_escapetbl.__index = function()
		decodeerror("invalid escape sequence")
	end
	setmetatable(f_str_escapetbl, f_str_escapetbl)

	local f_str_surrogate_prev = 0
	local function f_str_subst(ch, ucode)
		if ch == 'u' then
			local c1, c2, c3, c4, rest = byte(ucode, 1, 5)
			ucode = f_str_hextbl[c1-47] * 0x1000 +
			        f_str_hextbl[c2-47] * 0x100 +
			        f_str_hextbl[c3-47] * 0x10 +
			        f_str_hextbl[c4-47]
			if ucode ~= inf then
				if ucode < 0x80 then  -- 1byte
					if rest then
						return char(ucode, rest)
					end
					return char(ucode)
				elseif ucode < 0x800 then  -- 2bytes
					c1 = floor(ucode / 0x40)
					c2 = ucode - c1 * 0x40
					c1 = c1 + 0xC0
					c2 = c2 + 0x80
					if rest then
						return char(c1, c2, rest)
					end
					return char(c1, c2)
				elseif ucode < 0xD800 or 0xE000 <= ucode then  -- 3bytes
					c1 = floor(ucode / 0x1000)
					ucode = ucode - c1 * 0x1000
					c2 = floor(ucode / 0x40)
					c3 = ucode - c2 * 0x40
					c1 = c1 + 0xE0
					c2 = c2 + 0x80
					c3 = c3 + 0x80
					if rest then
						return char(c1, c2, c3, rest)
					end
					return char(c1, c2, c3)
				elseif 0xD800 <= ucode and ucode < 0xDC00 then  -- surrogate pair 1st
					if f_str_surrogate_prev == 0 then
						f_str_surrogate_prev = ucode
						if not rest then
							return ''
						end
						decodeerror("1st surrogate pair byte not continued by 2nd")
					end
					f_str_surrogate_prev = 0
					decodeerror("two contiguous 1st surrogate pair bytes")
				else  -- surrogate pair 2nd
					if f_str_surrogate_prev ~= 0 then
						ucode = 0x10000 +
								(f_str_surrogate_prev - 0xD800) * 0x400 +
								(ucode - 0xDC00)
						f_str_surrogate_prev = 0
						c1 = floor(ucode / 0x40000)
						ucode = ucode - c1 * 0x40000
						c2 = floor(ucode / 0x1000)
						ucode = ucode - c2 * 0x1000
						c3 = floor(ucode / 0x40)
						c4 = ucode - c3 * 0x40
						c1 = c1 + 0xF0
						c2 = c2 + 0x80
						c3 = c3 + 0x80
						c4 = c4 + 0x80
						if rest then
							return char(c1, c2, c3, c4, rest)
						end
						return char(c1, c2, c3, c4)
					end
					decodeerror("2nd surrogate pair byte appeared without 1st")
				end
			end
			decodeerror("invalid unicode codepoint literal")
		end
		if f_str_surrogate_prev ~= 0 then
			f_str_surrogate_prev = 0
			decodeerror("1st surrogate pair byte not continued by 2nd")
		end
		return f_str_escapetbl[ch] .. ucode
	end

	-- caching interpreted keys for speed
	local f_str_keycache = setmetatable({}, {__mode="v"})

	local function f_str(iskey)
		local newpos = pos-2
		local pos2 = pos
		local c1, c2
		repeat
			newpos = find(json, '"', pos2, true)  -- search '"'
			if not newpos then
				decodeerror("unterminated string")
			end
			pos2 = newpos+1
			while true do  -- skip preceding '\\'s
				c1, c2 = byte(json, newpos-2, newpos-1)
				if c2 ~= 0x5C or c1 ~= 0x5C then
					break
				end
				newpos = newpos-2
			end
		until c2 ~= 0x5C  -- leave if '"' is not preceded by '\'

		local str = sub(json, pos, pos2-2)
		pos = pos2

		if iskey then  -- check key cache
			pos2 = f_str_keycache[str]
			if pos2 then
				return pos2
			end
			pos2 = str
		end

		if find(str, f_str_ctrl_pat) then
			decodeerror("unescaped control string")
		end
		if find(str, '\\', 1, true) then  -- check whether a backslash exists
			-- We need to grab 4 characters after the escape char,
			-- for encoding unicode codepoint to UTF-8.
			-- As we need to ensure that every first surrogate pair byte is
			-- immediately followed by second one, we grab upto 5 characters and
			-- check the last for this purpose.
			str = gsub(str, '\\(.)([^\\]?[^\\]?[^\\]?[^\\]?[^\\]?)', f_str_subst)
			if f_str_surrogate_prev ~= 0 then
				f_str_surrogate_prev = 0
				decodeerror("1st surrogate pair byte not continued by 2nd")
			end
		end
		if iskey then  -- commit key cache
			f_str_keycache[pos2] = str
		end
		return str
	end

	--[[
		Arrays, Objects
	--]]
	-- array
	local function f_ary()
		local ary = {} -- no issue with lua numerical index

		f, pos = find(json, '^[ \n\r\t]*', pos)
		pos = pos+1

		local i = 0
		if byte(json, pos) ~= 0x5D then  -- check closing bracket ']' which means the array empty
			local newpos = pos-1
			repeat
				i = i+1
				f = dispatcher[byte(json,newpos+1)]  -- parse value
				pos = newpos+2
				ary[i] = f()
				f, newpos = find(json, '^[ \n\r\t]*,[ \n\r\t]*', pos)  -- check comma
			until not newpos

			f, newpos = find(json, '^[ \n\r\t]*%]', pos)  -- check closing bracket
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
		local obj = newobj and newobj() or {}

		f, pos = find(json, '^[ \n\r\t]*', pos)
		pos = pos+1
		if byte(json, pos) ~= 0x7D then  -- check closing bracket '}' which means the object empty
			local newpos = pos-1

			repeat
				pos = newpos+1
				if byte(json, pos) ~= 0x22 then  -- check '"'
					decodeerror("not key")
				end
				pos = pos+1
				local key = f_str(true)  -- parse key

				-- optimized for compact json
				-- c1, c2 == ':', <the first char of the value> or
				-- c1, c2, c3 == ':', ' ', <the first char of the value>
				f = f_err
				do
					local c1, c2, c3 = byte(json, pos, pos+3)
					if c1 == 0x3A then
						newpos = pos
						if c2 == 0x20 then
							newpos = newpos+1
							c2 = c3
						end
						f = dispatcher[c2]
					end
				end
				if f == f_err then  -- read a colon and arbitrary number of spaces
					f, newpos = find(json, '^[ \n\r\t]*:[ \n\r\t]*', pos)
					if not newpos then
						decodeerror("no colon after a key")
					end
				end
				f = dispatcher[byte(json, newpos+1)]  -- parse value
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
		The jump table to dispatch a parser for a value,
		indexed by the code of the value's first char.
		Nil key means the end of json.
	--]]
	dispatcher = {
		       f_err, f_err, f_err, f_err, f_err, f_err, f_err,
		f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err,
		f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err,
		f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err,
		f_err, f_err, f_str, f_err, f_err, f_err, f_err, f_err,
		f_err, f_err, f_err, f_err, f_err, f_mns, f_err, f_err,
		f_zro, f_num, f_num, f_num, f_num, f_num, f_num, f_num,
		f_num, f_num, f_err, f_err, f_err, f_err, f_err, f_err,
		f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err,
		f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err,
		f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err,
		f_err, f_err, f_err, f_ary, f_err, f_err, f_err, f_err,
		f_err, f_err, f_err, f_err, f_err, f_err, f_fls, f_err,
		f_err, f_err, f_err, f_err, f_err, f_err, f_nul, f_err,
		f_err, f_err, f_err, f_err, f_tru, f_err, f_err, f_err,
		f_err, f_err, f_err, f_obj, f_err, f_err, f_err, f_err,
	}
	dispatcher[0] = f_err
	dispatcher.__index = function()
		decodeerror("unexpected termination")
	end
	setmetatable(dispatcher, dispatcher)

	--[[
		run decoder
	--]]
	local function decode(json_, pos_, nullv_, arraylen_, newobj_)
		json, pos, nullv, arraylen, newobj = json_, pos_, nullv_, arraylen_, newobj_

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
