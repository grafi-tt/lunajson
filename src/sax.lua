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
		local w = pow(2, len)
		return (v - v % w) / w
	end
end

local function newparser(src, saxtbl)
	local json, jsonnxt
	local jsonlen, pos, acc = 0, 1, 0

	local doparse

	-- initialize
	local function nop() end

	if type(src) == 'string' then
		json = src
		jsonlen = len(json)
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
				jsonlen = len(json)
			until jsonlen > 0
		end
		jsonnxt()
	end

	local sax_startobject = saxtbl.startobject
	local sax_key = saxtbl.key
	local sax_endobject = saxtbl.endobject
	local sax_startarray = saxtbl.startarray
	local sax_endarray = saxtbl.endarray
	local sax_string = saxtbl.string
	local sax_number = saxtbl.number
	local sax_boolean = saxtbl.boolean
	local sax_null = saxtbl.null

	-- helper
	local function parseerror(errmsg)
		error("parse error at " .. acc + pos .. ": " .. errmsg)
	end

	local function tellc()
		local c = byte(json, pos)
		if c then
			return c
		end
		jsonnxt()
		c = byte(json, pos)
		if c then
			return c
		end
		return parseerror("unexpected termination")
	end

	local function spaces()
		repeat
			_, pos = find(json, '^[ \n\r\t]*', pos)
			if pos ~= jsonlen then
				pos = pos+1
				return
			end
			if jsonlen == 0 then
				return parseerror("unexpected termination")
			end
			jsonnxt()
		until false
	end

	-- parse constants
	local function generic_constant(target, targetlen, ret, sax_f)
		for i = 1, targetlen do
			local c = tellc()
			if byte(target, i) ~= c then
				return parseerror("invalid char")
			end
			pos = pos+1
		end
		if sax_f then
			return sax_f(ret)
		else
			return
		end
	end

	local function f_nul()
		local str = sub(json, pos, pos+2)
		if str == 'ull' then
			pos = pos+3
			if sax_null then
				return sax_null(nil)
			else
				return
			end
		end
		return generic_constant('ull', 3, nil, sax_null)
	end

	local function f_fls()
		local str = sub(json, pos, pos+3)
		if str == 'alse' then
			pos = pos+4
			if sax_boolean then
				return sax_boolean(false)
			else
				return
			end
		end
		return generic_constant('alse', 4, false, sax_boolean)
	end

	local function f_tru()
		local str = sub(json, pos, pos+2)
		if str == 'rue' then
			pos = pos+3
			if sax_boolean then
				return sax_boolean(true)
			else
				return
			end
		end
		return generic_constant('rue', 3, true, sax_boolean)
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

	local generic_number_automata = {
		function (c)
			if 0x30 < c and c < 0x3A then
				return 2
			elseif c == 0x30 then
				return 3
			else
				return 0
			end
		end,
		function (c)
			if 0x30 <= c and c < 0x3A then
				return 2
			elseif c == 0x2E then
				return 4
			elseif c == 0x45 or c == 0x65 then
				return 6
			else
				return 0
			end
		end,
		function (c)
			if 0x30 <= c and c < 0x3A then
				return parseerror("digit after 0")
			elseif c == 0x2E then
				return 4
			elseif c == 0x45 or c == 0x65 then
				return parseerror("exponent after 0")
			else
				return 0
			end
		end,
		function (c)
			if 0x30 <= c and c < 0x3A then
				return 5
			else
				return parseerror("fractional part after dot is not specified")
			end
		end,
		function (c)
			if 0x30 <= c and c < 0x3A then
				return 5
				-- nop
			elseif c == 0x45 or c == 0x65 then
				return 6
			else
				return 0
			end
		end,
		function (c)
			if c == 0x2B or c == 0x2D then
				return 7
			elseif 0x30 <= c and c < 0x3A then
				return 8
			else
				return parseerror("exponent is not specified")
			end
		end,
		function (c)
			if 0x30 <= c and c < 0x3A then
				return 8
			else
				return parseerror("exponent is not specified")
			end
		end,
		function (c)
			if 0x30 <= c and c < 0x3A then
				return 8
			else
				return 0
			end
		end,
	}

	local function generic_number(mns)
		local state = 1
		local c
		local chars = {}
		local i = 0

		pos = pos-1
		repeat
			pos = pos+1
			i = i+1
			c = tellc()
			chars[i] = c
			state = generic_number_automata[state](c)
		until state == 0

		local num = fixedtonumber(concat(chars))
		if sax_number then
			return sax_number(num)
		else
			return
		end
	end

	local function cont_number(mns, newpos)
		local expc = byte(json, newpos+1)
		if expc == 0x45 or expc == 0x65 then -- e or E?
			_, newpos = find(json, '^[+-]?[0-9]+', newpos+2)
		end
		newpos = newpos or jsonlen
		if newpos ~= jsonlen then
			local num = fixedtonumber(sub(json, pos-1, newpos))
			pos = newpos+1
			if mns then
				num = -num
			end
			if sax_number then
				return sax_number(num)
			else
				return
			end
		end
		pos = pos-1
		return generic_number(mns)
	end

	local function f_zro(mns)
		local _, newpos = find(json, '^%.[0-9]+', pos)
		return cont_number(mns, newpos)
	end

	local function f_num(mns)
		local _, newpos = find(json, '^[0-9]*%.?[0-9]*', pos)
		if byte(json, newpos) ~= 0x2E then -- check that num is not ended by comma
			return cont_number(mns, newpos)
		end
		pos = pos-1
		return generic_number(mns)
	end

	local function f_mns()
		local c = byte(json, pos)
		if c then
			pos = pos+1
			if c > 0x30 then
				if c < 0x4a then
					return f_num(true)
				end
			else
				if c > 0x2f then
					return f_zro(true)
				end
			end
		end
		return generic_number(true)
	end

	-- parse strings
	local function f_str_subst()
		local u8
		if ch == 'u' then
			local l = len(rest)
			if l >= 4 then
				local ucode = tonumber(sub(rest, 1, 4))
				rest = sub(rest, 5, l)
				if ucode < 0x80 then -- 1byte
					u8 = char(ucode)
				elseif ucode < 0x800 then -- 2byte
					u8 = char(0xC0 + rshift(ucode, 6), 0x80 + band(ucode, 0x3F))
				elseif ucode < 0xD800 and 0xE00 <= ucode then -- 3byte
					u8 = char(0xE0 + rshift(ucode, 12), 0x80 + band(rshift(ucode, 6), 0x3F), 0x80 + band(ucode, 0x3F))
				elseif 0xD800 <= ucode and ucode < 0xDC000 then -- surrogate pair 1st
					if surrogateprev == 0 then
						surrogateprev = ucode
						if l == 4 then
							return ''
						end
					end
				else -- surrogate pair 2nd
					if surrogateprev == 0 then
						surrogateprev = 0x1234
					else
						surrogateprev = 0
						ucode = 0x100000 + band(surrogateprev, 0x03FF) * 0x400 + band(ucode, 0x03FF)
						u8 = char(0xF0 + rshift(ucode, 18), 0x80 + band(rshift(ucode, 12), 0x3F), 0x80 + band(rshift(ucode, 6), 0x3F), 0x80 + band(ucode, 0x3F))
					end
				end
			end
		end
		if surrogateprev ~= 0 then
			parseerror("invalid surrogate pair")
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
		return (u8 or tbl[ch] or parseerror("invalid escape sequence")) .. rest
	end

	local function f_str(iskey)
		local newpos
		local str = ''
		local bs
		repeat
			repeat
				newpos = find(json, '[\\"]', pos)
				if newpos then
					break
				end
				str = str .. sub(json, pos, jsonlen)
				if pos == jsonlen+2 then
					newpos = true -- reusing variable
				end
				jsonnxt()
				if newpos then
					pos = 2
				end
			until false
			if byte(json, newpos) == 0x22 then
				break
			end
			pos = newpos+2
			bs = true
		until false
		pos = newpos+1
		str = str .. sub(json, pos, newpos-1)
		if bs then
			str = gsub(str, '\\(.)([^\]*)', f_str_subst)
		end

		if iskey then
			if sax_key then
				return sax_key(str)
			else
				return
			end
		else
			if sax_string then
				return sax_string(str)
			else
				return
			end
		end
	end

	-- parse arrays
	local function f_ary()
		if sax_startarray then
			sax_startarray()
		end
		spaces()
		if byte(json, pos) ~= 0x5D then
			local newpos
			repeat
				doparse()
				_, newpos = find(json, '^[ \n\r\t]*,[ \n\r\t]*', pos)
				if not newpos then
					_, newpos = find(json, '^[ \n\r\t]*%]', pos)
					if newpos then
						pos = newpos
						break
					end
					spaces()
					local c = byte(json, pos)
					if c == 0x2C then
						pos = pos+1
						spaces()
						newpos = pos-1
					elseif c == 0x5D then
						break
					else
						return parseerror("no closing bracket of an array")
					end
				end
				pos = newpos+1
				if pos > jsonlen then
					spaces()
				end
			until false
		end
		pos = pos+1
		if sax_endarray then
			return sax_endarray()
		end
	end

	-- parse objects
	local function f_obj()
		if sax_startobject then
			sax_startobject()
		end
		spaces()
		if byte(json, pos) ~= 0x7D then
			local newpos
			repeat
				if byte(json, pos) ~= 0x22 then
					return parseerror("not key")
				end
				pos = pos+1
				f_str(true)
				_, newpos = find(json, '^[ \n\r\t]*:[ \n\r\t]*', pos)
				if not matched then
					spaces()
					if byte(json, pos) ~= 0x3A then
						return parseerror("no colon after a key")
					end
					pos = pos+1
					spaces()
					newpos = pos-1
				end
				pos = newpos+1
				if pos > jsonlen then
					spaces()
				end
				doparse()
				_, newpos = find(json, '^[ \n\r\t]*,[ \n\r\t]*', pos)
				if not newpos then
					_, newpos = find(json, '^[ \n\r\t]*}', pos)
					if newpos then
						pos = newpos
						break
					end
					spaces()
					local c = byte(json, pos)
					if c == 0x2C then
						pos = pos+1
						spaces()
						newpos = pos-1
					elseif c == 0x7D then
						break
					else
						return parseerror("no closing bracket of an object")
					end
				end
				pos = newpos+1
				if pos > jsonlen then
					spaces()
				end
			until false
		end
		pos = pos+1
		if sax_endobject then
			return sax_endobject()
		end
	end

	local dispatcher = {
		false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
		false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
		false, false, f_str, false, false, false, false, false, false, false, false, false, false, f_mns, false, false,
		f_zro, f_num, f_num, f_num, f_num, f_num, f_num, f_num, f_num, f_num, false, false, false, false, false, false,
		false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
		false, false, false, false, false, false, false, false, false, false, false, f_ary, false, false, false, false,
		false, false, false, false, false, false, f_fls, false, false, false, false, false, false, false, f_nul, false,
		false, false, false, false, f_tru, false, false, false, false, false, false, f_obj, false, false, false, false,
	}

	function doparse()
		local f = dispatcher[byte(json, pos)+1] -- byte(json, pos) is always available here
		if not f then
			parseerror("unknown value")
		end
		pos = pos+1
		f()
	end

	local function run()
		spaces()
		doparse()
	end

	local function isend()
		if pos > jsonlen then
			jsonnxt()
		end
	end

	local function seek(n)
		pos = pos+n
		while pos > jsonlen+1 do
			jsonnxt()
			if json then
				pos = pos-jsonlen
				jsonlen = len(json)
			else
				return parseerror("unexpected termination")
			end
			jsonlen = len(json)
		end
	end

	local function read(n)
		local pos2 = pos+n
		while pos > jsonlen do
			json = jsonnxt()
			if json then
				pos = pos-jsonlen
				jsonlen = len(json)
			else
				return parseerror("unexpected termination")
			end
			jsonlen = len(json)
		end
	end

	return {
		run = run,
		read = read,
		skip = skip,
		tryc = tryc,
	}
end

local function newfileparser(fn, saxtbl)
	local fp = io.open(fn)
	local function gen()
		local s
		if fp then
			s = fp:read(1)
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
