local error = error
local byte, find, format, gsub, match, rep = string.byte, string.find, string.format,  string.gsub, string.match, string.rep
local concat = table.concat
local tostring = tostring
local pairs, type = pairs, type
local setmetatable = setmetatable
local huge, tiny = 1/0, -1/0

local set_cache = setmetatable({}, { __weak = "k" })
local basic = {
	start_array = '[',
	end_array = ']',
	start_object = '{',
	end_object = '}',
	split_element = ','
}
local delim_tmpls = {
    start_array = '[\n%s%%s',
    end_array = '\n%%s]',
    start_object = '{\n%s%%s',
    end_object = '\n%%s}',
    split_element = ',\n%s%%s'
}
local f_string_esc_pat
if _VERSION == "Lua 5.1" then
	-- use the cluttered pattern because lua 5.1 does not handle \0 in a pattern correctly
	f_string_esc_pat = '[^ -!#-[%]^-\255]'
else
	f_string_esc_pat = '[\0-\31"\\]'
end

local one_space = " "

local function newencoder()
	local active_delims
	local v, nullv, colon
	local i, builder, visited
	
	local function f_tostring(v)
		builder[i] = tostring(v)
		i = i+1
	end

	local radixmark = match(tostring(0.5), '[^0-9]')
	local delimmark = match(tostring(12345.12345), '[^0-9' .. radixmark .. ']')
	if radixmark == '.' then
		radixmark = nil
	end

	local radixordelim
	if radixmark or delimmark then
		radixordelim = true
		if radixmark and find(radixmark, '%W') then
			radixmark = '%' .. radixmark
		end
		if delimmark and find(delimmark, '%W') then
			delimmark = '%' .. delimmark
		end
	end

	local f_number = function(n)
		if tiny < n and n < huge then
			local s = format("%.17g", n)
			if radixordelim then
				if delimmark then
					s = gsub(s, delimmark, '')
				end
				if radixmark then
					s = gsub(s, radixmark, '.')
				end
			end
			builder[i] = s
			i = i+1
			return
		end
		error('invalid number')
	end

	local doencode

	local f_string_subst = {
		['"'] = '\\"',
		['\\'] = '\\\\',
		['\b'] = '\\b',
		['\f'] = '\\f',
		['\n'] = '\\n',
		['\r'] = '\\r',
		['\t'] = '\\t',
		__index = function(_, c)
			return format('\\u00%02X', byte(c))
		end
	}
	setmetatable(f_string_subst, f_string_subst)

	local function f_string(s)
		builder[i] = '"'
		if find(s, f_string_esc_pat) then
			s = gsub(s, f_string_esc_pat, f_string_subst)
		end
		builder[i+1] = s
		builder[i+2] = '"'
		i = i+3
	end
	local function basic_f_table(o)
		if visited[o] then
			error("loop detected")
		end
		visited[o] = true

		local arraylen = o[0]
		if type(arraylen) == 'number' then -- arraylen available
			if arraylen == 0 then
				builder[i] = '[]'
			else
				builder[i] = active_delims.start_array
				i = i+1
				for j = 1, arraylen do
					doencode(o[j])
					builder[i] = active_delims.split_element
					i = i+1
				end
				if arraylen > 0 then
					i = i-1
				end
				builder[i] = active_delims.end_array
			end
		else
			tmp = o[1]
			if tmp ~= nil then -- detected as array
				builder[i] = active_delims.start_array
				i = i+1
				local j = 2
				repeat
					doencode(tmp)
					tmp = o[j]
					if tmp == nil then
						break
					end
					j = j+1
					builder[i] = active_delims.split_element
					i = i+1
				until false
				builder[i] = active_delims.end_array

			else -- detected as object
				builder[i] = active_delims.start_object
				i = i+1
				local tmp = i
				for k, v in pairs(o) do
					if type(k) ~= 'string' then
						error("non-string key")
					end
					f_string(k)
					builder[i] = colon
					i = i+1
					doencode(v)
					builder[i] = active_delims.split_element
					i = i+1
				end
				i = i-1
				if i > tmp then
					builder[i] = active_delims.end_object
				else
					builder[i] = '{}'
				end
			end
		end

		i = i+1
		visited[o] = nil
	end
	local f_table
	local dispatcher = {
		boolean = f_tostring,
		number = f_number,
		string = f_string,
		table = function(...) return f_table(...) end,
		__index = function()
			error("invalid type value")
		end
	}
	setmetatable(dispatcher, dispatcher)

	function doencode(v)
		if v == nullv then
			builder[i] = 'null'
			i = i+1
			return
		end
		return dispatcher[type(v)](v)
	end
	local delim_set, space, depth
	local delims_meta = {}
	function delims_meta:__index(k)
		local s = format(delim_set[k], rep(space, depth))
		self[k] = s
		return s
	end
	local function spaced_f_table(o)
		depth = depth + 1
		local delims = delim_set[depth]
		if not delims then
			delims = setmetatable({}, delims_meta)
			delim_set[depth] = delims
		end
		active_delims = delims
		basic_f_table(o)
		depth = depth - 1
		active_delims = delim_set[depth]
	end
	local function encode(v_, nullv_, _space)
		v, nullv, space = v_, nullv_, _space
		i, builder, visited = 1, {}, {}
		
		if type(space) == "number" then space = rep(one_space, space) end
		if type(space) ~= "string" or space == "" then
			active_delims = basic
			f_table = basic_f_table
			colon = ":"
		else
			colon = ": "
			depth = -1
			f_table = spaced_f_table
			delim_set = set_cache[space]
			if not delim_set then
				delim_set = {}
				set_cache[space] = {}
				for k, v in pairs(delim_tmpls) do
					delim_set[k] = format(v, space)
				end
			end
		end

		doencode(v)
		return concat(builder)
	end

	return encode
end

return newencoder
