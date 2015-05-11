local error = error
local byte, char, find, gsub, match, sub =
	string.byte, string.char, string.find, string.gsub, string.match, string.sub
local tonumber = tonumber
local tostring, type, unpack = tonumber, type, table.unpack or unpack

local genstrlib
if _VERSION == "Lua 5.3" then
	genstrlib = require 'lunajson._str_lib_lua53'
else
	genstrlib = require 'lunajson._str_lib'
end

local _ENV = nil

local function nop() end

local function newparser(src, saxtbl)
	local json, jsonnxt
	local jsonlen, pos, acc = 0, 1, 0

	local dispatcher
	-- it is temporary for dispatcher[c] and
	-- dummy for 1st return value of find
	local f

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

	-- helper
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

	local function spaces()
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

	-- parse error
	local function f_err()
		parseerror('invalid value')
	end

	-- parse constants
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

	local function f_nul()
		if sub(json, pos, pos+2) == 'ull' then
			pos = pos+3
			return sax_null(nil)
		end
		return generic_constant('ull', 3, nil, sax_null)
	end

	local function f_fls()
		if sub(json, pos, pos+3) == 'alse' then
			pos = pos+4
			return sax_boolean(false)
		end
		return generic_constant('alse', 4, false, sax_boolean)
	end

	local function f_tru()
		if sub(json, pos, pos+2) == 'rue' then
			pos = pos+3
			return sax_boolean(true)
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
			return tonumber(gsub(s, '.', radixmark))
		end
	end

	local function generic_number(mns)
		local buf = {}
		local i = 1

		local c = byte(json, pos)
		pos = pos+1
		if c == 0x30 then
			buf[i] = c
			i = i+1
			c = tryc()
			pos = pos+1
			if c and 0x30 <= c and c < 0x3A then
				parseerror('invalid number')
			end
		else
			repeat
				buf[i] = c
				i = i+1
				c = tryc()
				pos = pos+1
			until not (c and 0x30 <= c and c < 0x3A)
		end
		if c == 0x2E then
			local oldi = i
			repeat
				buf[i] = c
				i = i+1
				c = tryc()
				pos = pos+1
			until not (c and 0x30 <= c and c < 0x3A)
			if oldi+1 == i then
				parseerror('invalid number')
			end
		end
		if c == 0x45 or c == 0x65 then
			repeat
				buf[i] = c
				i = i+1
				c = tryc()
				pos = pos+1
			until not (c and ((0x30 <= c and c < 0x3A) or (c == 0x2B or c == 0x2D)))
		end
		pos = pos-1

		local num = char(unpack(buf))
		num = fixedtonumber(num)
		if num then
			if mns then
				num = -num
			end
			return sax_number(num)
		end
		parseerror('invalid number')
	end

	local function f_zro(mns)
		local c = byte(json, pos)

		if c == 0x2E then
			local num = match(json, '^.[0-9]*', pos) -- skip 0
			local pos2 = #num
			if pos2 ~= 1 then
				pos2 = pos + pos2
				c = byte(json, pos2)
				if c == 0x45 or c == 0x65 then
					num = match(json, '^[^eE]*[eE][-+0-9]*', pos)
					pos2 = pos + #num
				end
				num = fixedtonumber(num)
				if num and pos2 <= jsonlen then
					pos = pos2
					if mns then
						num = 0.0-num
					else
						num = num-0.0
					end
					return sax_number(num)
				end
			end
			pos = pos-1
			return generic_number(mns)
		end

		if c ~= 0x2C and c ~= 0x5D and c ~= 0x7D then -- check e or E when unusual char is detected
			local pos2 = pos
			pos = pos-1
			if not c then
				return generic_number(mns)
			end
			if 0x30 <= c and c < 0x3A then
				parseerror('invalid number')
			end
			local num = match(json, '^.[eE][-+0-9]*', pos)
			if num then
				pos2 = pos + #num
				num = fixedtonumber(num)
				if not num or pos2 > jsonlen then
					return generic_number(mns)
				end
			end
			pos = pos2
		end

		if not mns then
			return sax_number(0.0)
		end
		return sax_number(-0.0)
	end

	local function f_num(mns)
		pos = pos-1
		local num = match(json, '^[0-9]+%.?[0-9]*', pos)
		local c = byte(num, -1)
		if c == 0x2E then -- check that num is not ended by comma
			return generic_number(mns)
		end

		local pos2 = pos + #num
		c = byte(json, pos2)
		if c == 0x45 or c == 0x65 then -- e or E?
			num = match(json, '^[^eE]*[eE][-+0-9]*', pos)
			pos2 = pos + #num
			num = fixedtonumber(num)
			if not num then
				return generic_number(mns)
			end
		else
			num = fixedtonumber(num)
		end
		if pos2 > jsonlen then
			return generic_number(mns)
		end
		pos = pos2

		if mns then
			num = 0.0-num
		else
			num = num-0.0
		end
		return sax_number(num)
	end

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

	-- parse strings
	local f_str_lib = genstrlib(parseerror)
	local f_str_surrogateok = f_str_lib.surrogateok
	local f_str_subst = f_str_lib.subst

	local function f_str(iskey)
		local pos2 = pos
		local newpos
		local str = ''
		local bs
		while true do
			while true do
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
			if byte(json, newpos) == 0x22 then
				break
			end
			pos2 = newpos+2
			bs = true
		end
		str = str .. sub(json, pos, newpos-1)
		pos = newpos+1

		if bs then
			str = gsub(str, '\\(.)([^\\]*)', f_str_subst)
			if not f_str_surrogateok() then
				parseerror("invalid surrogate pair")
			end
		end

		if iskey then
			return sax_key(str)
		end
		return sax_string(str)
	end

	-- parse arrays
	local function f_ary()
		sax_startarray()
		spaces()
		if byte(json, pos) ~= 0x5D then
			local newpos
			while true do
				f = dispatcher[byte(json, pos)]
				pos = pos+1
				f()
				f, newpos = find(json, '^[ \n\r\t]*,[ \n\r\t]*', pos)
				if not newpos then
					f, newpos = find(json, '^[ \n\r\t]*%]', pos)
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

	-- parse objects
	local function f_obj()
		sax_startobject()
		spaces()
		if byte(json, pos) ~= 0x7D then
			local newpos
			while true do
				if byte(json, pos) ~= 0x22 then
					parseerror("not key")
				end
				pos = pos+1
				f_str(true)
				f, newpos = find(json, '^[ \n\r\t]*:[ \n\r\t]*', pos)
				if not newpos then
					spaces()
					if byte(json, pos) ~= 0x3A then
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
				f = dispatcher[byte(json, pos)]
				pos = pos+1
				f()
				f, newpos = find(json, '^[ \n\r\t]*,[ \n\r\t]*', pos)
				if not newpos then
					f, newpos = find(json, '^[ \n\r\t]*}', pos)
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

	-- key should be non-nil
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
