local error, setmetatable, tonumber, tostring =
      error, setmetatable, tonumber, tostring
local byte, char, find, gsub, match, sub =
      string.byte, string.char, string.find, string.gsub, string.match, string.sub
local floor, inf =
      math.floor, math.huge
local mininteger, tointeger =
      math.mininteger or nil, math.tointeger or nil
local type, unpack = type, table.unpack or unpack

local _ENV = nil


local function nop() end

local function newparser(src, saxtbl)
	local json, jsonnxt
	local jsonlen, pos, acc = 0, 1, 0

	-- `f` is the temporary for dispatcher[c] and
	-- the dummy for the first return value of `find`
	local dispatcher, f

	-- initialize
	if type(src) == 'string' then
		json = src
		jsonlen = #json
		jsonnxt = function()
			json = ''
			jsonlen = 0
			jsonnxt = nop
		end
	else
		jsonnxt = function()
			acc = acc + jsonlen
			pos = 1
			repeat
				json = src()
				if not json then
					json = ''
					jsonlen = 0
					jsonnxt = nop
					return
				end
				jsonlen = #json
			until jsonlen > 0
		end
		jsonnxt()
	end

	local sax_startobject = saxtbl.startobject or nop
	local sax_key = saxtbl.key or nop
	local sax_endobject = saxtbl.endobject or nop
	local sax_startarray = saxtbl.startarray or nop
	local sax_endarray = saxtbl.endarray or nop
	local sax_string = saxtbl.string or nop
	local sax_number = saxtbl.number or nop
	local sax_boolean = saxtbl.boolean or nop
	local sax_null = saxtbl.null or nop

	--[[
		Helper
	--]]
	local function tryc()
		local c = byte(json, pos)
		if not c then
			jsonnxt()
			c = byte(json, pos)
		end
		return c
	end

	local function parseerror(errmsg)
		error("parse error at " .. acc + pos .. ": " .. errmsg)
	end

	local function tellc()
		return tryc() or parseerror("unexpected termination")
	end

	local function spaces() -- skip spaces and prepare the next char
		while true do
			f, pos = find(json, '^[ \n\r\t]*', pos)
			if pos ~= jsonlen then
				pos = pos+1
				return
			end
			if jsonlen == 0 then
				parseerror("unexpected termination")
			end
			jsonnxt()
		end
	end

	--[[
		Invalid
	--]]
	local function f_err()
		parseerror('invalid value')
	end

	--[[
		Constants
	--]]
	-- fallback slow constants parser
	local function generic_constant(target, targetlen, ret, sax_f)
		for i = 1, targetlen do
			local c = tellc()
			if byte(target, i) ~= c then
				parseerror("invalid char")
			end
			pos = pos+1
		end
		return sax_f(ret)
	end

	-- null
	local function f_nul()
		if sub(json, pos, pos+2) == 'ull' then
			pos = pos+3
			return sax_null(nil)
		end
		return generic_constant('ull', 3, nil, sax_null)
	end

	-- false
	local function f_fls()
		if sub(json, pos, pos+3) == 'alse' then
			pos = pos+4
			return sax_boolean(false)
		end
		return generic_constant('alse', 4, false, sax_boolean)
	end

	-- true
	local function f_tru()
		if sub(json, pos, pos+2) == 'rue' then
			pos = pos+3
			return sax_boolean(true)
		end
		return generic_constant('rue', 3, true, sax_boolean)
	end

	--[[
		Numbers
		Conceptually, the longest prefix that matches to `(0|[1-9][0-9]*)(\.[0-9]*)?([eE][+-]?[0-9]*)?`
		(in regexp) is captured as a number and its conformance to the JSON spec is checked.
	--]]
	-- deal with non-standard locales
	local radixmark = match(tostring(0.5), '[^0-9]')
	local fixedtonumber = tonumber
	if radixmark ~= '.' then -- deals with non-standard locales
		if find(radixmark, '%W') then
			radixmark = '%' .. radixmark
		end
		fixedtonumber = function(s)
			return tonumber(gsub(s, '.', radixmark))
		end
	end

	-- fallback slow parser
	local function generic_number(mns)
		local buf = {}
		local i = 1
		local is_int = true

		local c = byte(json, pos)
		pos = pos+1

		local function nxt()
			buf[i] = c
			i = i+1
			c = tryc()
			pos = pos+1
		end

		if c == 0x30 then
			nxt()
		else
			repeat nxt() until not (c and 0x30 <= c and c < 0x3A)
		end
		if c == 0x2E then
			is_int = false
			nxt()
			if not (c and 0x30 <= c and c < 0x3A) then
				parseerror('invalid number')
			end
			repeat nxt() until not (c and 0x30 <= c and c < 0x3A)
		end
		if c == 0x45 or c == 0x65 then
			is_int = false
			nxt()
			if c == 0x2B or c == 0x2D then
				nxt()
			end
			if not (c and 0x30 <= c and c < 0x3A) then
				parseerror('invalid number')
			end
			repeat nxt() until not (c and 0x30 <= c and c < 0x3A)
		end
		pos = pos-1

		local num = char(unpack(buf))
		num = fixedtonumber(num)
		if mns then
			num = -num
			if num == mininteger and is_int then
				num = mininteger
			end
		end
		return sax_number(num)
	end

	-- `0(\.[0-9]*)?([eE][+-]?[0-9]*)?`
	local function f_zro(mns)
		local postmp = pos
		local num
		local numret = 0
		local c = byte(json, postmp)

		if c == 0x2E then -- is this `.`?
			num = match(json, '^.[0-9]*', pos) -- skipping 0
			c = #num
			if c == 1 then
				pos = pos-1
				return generic_number(mns)
			end
			postmp = pos + c
			c = byte(json, postmp)
		end

		if c == 0x45 or c == 0x65 then -- is this e or E?
			c = match(json, '^[^eE]*[eE][-+]?[0-9]+', pos)
			if not c then
				pos = pos-1
				return generic_number(mns)
			end
			if num then
				num = c
			else -- `0e.*` is always 0.0
				numret = 0.0
			end
			postmp = pos + #c
		end

		if postmp > jsonlen then
			pos = pos-1
			return generic_number(mns)
		end
		pos = postmp
		if num then
			numret = fixedtonumber(num)
		end
		if mns then
			numret = -numret
		end
		return sax_number(numret)
	end

	-- `[1-9][0-9]*(\.[0-9]*)?([eE][+-]?[0-9]*)?`
	local function f_num(mns)
		pos = pos-1
		local num = match(json, '^.[0-9]*%.?[0-9]*', pos)
		if byte(num, -1) == 0x2E then
			return generic_number(mns)
		end
		local postmp = pos + #num
		local c = byte(json, postmp)

		if c == 0x45 or c == 0x65 then -- e or E?
			num = match(json, '^[^eE]*[eE][-+]?[0-9]+', pos)
			if not num then
				return generic_number(mns)
			end
			postmp = pos + #num
		end

		if postmp > jsonlen then
			return generic_number(mns)
		end
		pos = postmp
		c = fixedtonumber(num)
		if mns then
			c = -c
			if c == mininteger then
				if match(num, '^[0-9]*$') then
					c = tointeger(c)
				end
			end
		end
		return sax_number(c)
	end

	-- skip minus sign
	local function f_mns()
		local c = byte(json, pos) or tellc()
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
		parseerror("invalid number")
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

	local function f_str(iskey)
		local pos2 = pos
		local newpos
		local str = ''
		local bs
		while true do
			while true do -- search '\' or '"'
				newpos = find(json, '[\\"]', pos2)
				if newpos then
					break
				end
				str = str .. sub(json, pos, jsonlen)
				if pos2 == jsonlen+2 then
					pos2 = 2
				else
					pos2 = 1
				end
				jsonnxt()
			end
			if byte(json, newpos) == 0x22 then -- break if '"'
				break
			end
			pos2 = newpos+2 -- skip '\<char>'
			bs = true -- remember that backslash occurs
		end
		str = str .. sub(json, pos, newpos-1)
		pos = newpos+1

		if bs then -- check if backslash occurs
			str = gsub(str, '\\(.)([^\\]*)', f_str_subst) -- interpret escapes
			if f_str_surrogate_prev ~= 0 then
				f_str_surrogate_prev = 0
				decodeerror("invalid surrogate pair")
			end
		end

		if iskey then
			return sax_key(str)
		end
		return sax_string(str)
	end

	--[[
		Arrays, Objects
	--]]
	-- arrays
	local function f_ary()
		sax_startarray()
		spaces()
		if byte(json, pos) ~= 0x5D then -- check the closing bracket ']', that consists an empty array
			local newpos
			while true do
				f = dispatcher[byte(json, pos)] -- parse value
				pos = pos+1
				f()
				f, newpos = find(json, '^[ \n\r\t]*,[ \n\r\t]*', pos) -- check comma
				if not newpos then
					f, newpos = find(json, '^[ \n\r\t]*%]', pos) -- check closing bracket
					if newpos then
						pos = newpos
						break
					end
					spaces() -- since the current chunk can be ended, skip spaces toward following chunks
					local c = byte(json, pos)
					if c == 0x2C then -- check comma again
						pos = pos+1
						spaces()
						newpos = pos-1
					elseif c == 0x5D then -- check closing bracket again
						break
					else
						parseerror("no closing bracket of an array")
					end
				end
				pos = newpos+1
				if pos > jsonlen then
					spaces()
				end
			end
		end
		pos = pos+1
		return sax_endarray()
	end

	-- objects
	local function f_obj()
		sax_startobject()
		spaces()
		if byte(json, pos) ~= 0x7D then -- check the closing bracket `}`, that consists an empty object
			local newpos
			while true do
				if byte(json, pos) ~= 0x22 then
					parseerror("not key")
				end
				pos = pos+1
				f_str(true)
				f, newpos = find(json, '^[ \n\r\t]*:[ \n\r\t]*', pos) -- check colon
				if not newpos then
					spaces() -- since the current chunk can be ended, skip spaces toward following chunks
					if byte(json, pos) ~= 0x3A then -- check colon again
						parseerror("no colon after a key")
					end
					pos = pos+1
					spaces()
					newpos = pos-1
				end
				pos = newpos+1
				if pos > jsonlen then
					spaces()
				end
				f = dispatcher[byte(json, pos)] -- parse value
				pos = pos+1
				f()
				f, newpos = find(json, '^[ \n\r\t]*,[ \n\r\t]*', pos) -- check comma
				if not newpos then
					f, newpos = find(json, '^[ \n\r\t]*}', pos) -- check closing bracket
					if newpos then
						pos = newpos
						break
					end
					spaces() -- since the current chunk can be ended, skip spaces toward following chunks
					local c = byte(json, pos)
					if c == 0x2C then -- check comma again
						pos = pos+1
						spaces()
						newpos = pos-1
					elseif c == 0x7D then -- check closing bracket again
						break
					else
						parseerror("no closing bracket of an object")
					end
				end
				pos = newpos+1
				if pos > jsonlen then
					spaces()
				end
			end
		end
		pos = pos+1
		return sax_endobject()
	end

	--[[
		The jump table to dispatch a parser for a value, indexed by the code of the value's first char.
		Key should be non-nil.
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

	--[[
		public funcitons
	--]]
	local function run()
		spaces()
		f = dispatcher[byte(json, pos)]
		pos = pos+1
		f()
	end

	local function read(n)
		if n < 0 then
			error("the argument must be non-negative")
		end
		local pos2 = (pos-1) + n
		local str = sub(json, pos, pos2)
		while pos2 > jsonlen and jsonlen ~= 0 do
			jsonnxt()
			pos2 = pos2 - (jsonlen - (pos-1))
			str = str .. sub(json, pos, pos2)
		end
		if jsonlen ~= 0 then
			pos = pos2+1
		end
		return str
	end

	local function tellpos()
		return acc + pos
	end

	return {
		run = run,
		tryc = tryc,
		read = read,
		tellpos = tellpos,
	}
end

local function newfileparser(fn, saxtbl)
	local fp = io.open(fn)
	local function gen()
		local s
		if fp then
			s = fp:read(8192)
			if not s then
				fp:close()
				fp = nil
			end
		end
		return s
	end
	return newparser(gen, saxtbl)
end

return {
	newparser = newparser,
	newfileparser = newfileparser
}
