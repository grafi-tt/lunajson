local byte = string.byte
local char = string.char
local find = string.find
local gsub = string.gsub
local match = string.match
local sub = string.sub
local floor = math.floor
local tonumber = tonumber

local genstrlib
if _VERSION == "Lua 5.3" then
	genstrlib = require 'lunajson._str_lib_lua53'
else
	genstrlib = require 'lunajson._str_lib'
end

local function newparser(src, saxtbl)
	local json, jsonnxt
	local jsonlen, pos, acc = 0, 1, 0

	local dispatcher
	-- it is temporary for dispatcher[c] and
	-- dummy for 1st return value of find
	local f

	-- initialize
	local function nop() end

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
		parseerror("unexpected termination")
	end

	local function spaces()
		while true do
			_, pos = find(json, '^[ \n\r\t]*', pos)
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
		if sax_f then
			return sax_f(ret)
		else
			return
		end
	end

	local function f_nul()
		if sub(json, pos, pos+2) == 'ull' then
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
		if sub(json, pos, pos+3) == 'alse' then
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
		if sub(json, pos, pos+2) == 'rue' then
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
			return tonumber(gsub(s, '.', radixmark))
		end
	end

	local function generic_number(mns)
		local newpos

		local str = ''
		repeat
			_, newpos = find(json, '^[-+0-9.eE]*', pos)
			str = str .. sub(json, pos, newpos)
			pos = newpos
			if pos ~= jsonlen then
				pos = pos+1
				break
			end
			jsonnxt()
		until jsonlen == 0

		local c = byte(str)
		if c == 0x30 then
			_, newpos = find(str, '^%.[0-9]+', 2)
			if not newpos then
				newpos = 1
			end
		elseif 0x30 < c and c < 0x3A then
			_, newpos = find(str, '^[0-9]*%.?[0-9]*', 2)
			if byte(str, newpos) == 0x2E then
				parseerror('invalid number')
			end
		else
			parseerror('invalid number')
		end

		c = byte(str, newpos+1)
		if c == 0x45 or c == 0x65 then
			_, newpos = find(str, '^[+-]?[0-9]+', newpos+2)
		end

		if newpos ~= #str then
			parseerror('invalid number')
		end
		local num = fixedtonumber(str)
		if mns then
			num = -num
		end
		if sax_number then
			return sax_number(num)
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
		if byte(json, pos) ~= 0x2E then
			return cont_number(mns, pos-1)
		end
		local _, newpos = find(json, '^[0-9]+', pos+1)
		if newpos then
			return cont_number(mns, newpos)
		end
		pos = pos-1
		return generic_number(mns)
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
		f = dispatcher[c]
		if f == f_num or f == f_zro then
			pos = pos+1
			return f(true)
		end
		if not c then
			c = tellc()
			f = dispatcher[c]
			if f == f_num or f == f_zro then
				pos = pos+1
				return f(true)
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
			while true do
				f = dispatcher[byte(json, pos)]
				pos = pos+1
				f()
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
			while true do
				if byte(json, pos) ~= 0x22 then
					parseerror("not key")
				end
				pos = pos+1
				f_str(true)
				_, newpos = find(json, '^[ \n\r\t]*:[ \n\r\t]*', pos)
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
		if sax_endobject then
			return sax_endobject()
		end
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

	local function tryc()
		local c = byte(json, pos)
		if not c then
			jsonnxt()
			c = byte(json, pos)
		end
		return c
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
		pos = pos2+1
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
