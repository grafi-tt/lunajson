local byte = string.byte
local find = string.find
local format = string.format
local gsub = string.gsub
local match = string.match
local rawequal = rawequal
local tostring = tostring
local pairs = pairs
local type = type

local function encode(v, nullv)
	local i = 1
	local builder = {}
	local visited = {}

	local function f_tostring(v)
		builder[i] = tostring(v)
		i = i+1
	end

	local f_number = function(n)
		builder[i] = format("%.17g", n)
		i = i+1
	end

	do
		local radixmark = match(tostring(0.5), '[^0-9]')
		local delimmark = match(tostring(123456789.123456789), '[^0-9' .. radixmark .. ']')
		if radixmark == '.' then
			radixmark = nil
		end

		if radixmark or delimmark then
			if radixmark and find(radixmark, '%W') then
				radixmark = '%' .. radixmark
			end
			if delimmark and find(selimmark, '%W') then
				delimmark = '%' .. delimmark
			end
			f_number = function(n)
				local s = format("%.17g", n)
				if delimmark then
					s = gsub(s, delimmark, '')
				end
				if radixmark then
					s = gsub(s, radixmark, '.')
				end
				builder[i] = s
				i = i+1
			end
		end
	end

	local dodecode

	local f_string_subst = {
		['"'] = '\\"',
		['\\'] = '\\\\',
		['\b'] = '\\b',
		['\f'] = '\\f',
		['\n'] = '\\n',
		['\r'] = '\\r',
		['\t'] = '\\t',
		__index = function(_, c)
			return format('\\u00%02X', tostring(byte(c)))
		end
	}
	setmetatable(f_string_subst, f_string_subst)

	local function f_string(s)
		-- use the cluttered pattern because lua 5.1 does not handle \0 in a pattern correctly
		local pat = '[^\32-\33\35-\91\93-\255]'
		builder[i] = '"'
		if find(s, pat) then
			s = gsub(s, pat, f_string_subst)
		end
		builder[i+1] = s
		builder[i+2] = '"'
		i = i+3
	end

	local function f_table(o)
		if visited[o] then
			error("loop detected")
		end
		visited[o] = true

		local alen = o[0]
		if type(alen) == 'number' then
			builder[i] = '['
			i = i+1
			for j = 1, alen do
				dodecode(o[j])
				builder[i] = ','
				i = i+1
			end
			if alen > 0 then
				i = i-1
			end
			builder[i] = ']'
			i = i+1
			return
		end

		local v = o[1]
		if v ~= nil then
			builder[i] = '['
			i = i+1
			local j = 2
			repeat
				dodecode(v)
				v = o[j]
				if v == nil then
					break
				end
				j = j+1
				builder[i] = ','
				i = i+1
			until false
			builder[i] = ']'
			i = i+1
			return
		end

		builder[i] = '{'
		i = i+1
		local oldi = i
		for k, v in pairs(o) do
			if type(k) ~= 'string' then
				error("non-string key")
			end
			f_string(k)
			builder[i] = ':'
			i = i+1
			dodecode(v)
			builder[i] = ','
			i = i+1
		end
		if i > oldi then
			i = i-1
		end
		builder[i] = '}'
		i = i+1
	end

	local dispatcher = {
		boolean = f_tostring,
		number = f_tostring,
		string = f_string,
		table = arraylen and f_table_arraylen or f_table,
		__index = function()
			error("invalid type value")
		end
	}
	setmetatable(dispatcher, dispatcher)

	function dodecode(v)
		if rawequal(v, nullv) then
			builder[i] = 'null'
			i = i+1
			return
		end
		dispatcher[type(v)](v)
	end

	-- exec
	dodecode(v)
	return table.concat(builder)
end

return {
	encode = encode
}
