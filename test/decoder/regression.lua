-- Regression tests which cannot be expressed as a single JSON file.
local util = require 'util'

-- build escape sequences at runtime to keep this source plain ASCII
local function u(hex)
	return '\\' .. 'u' .. hex
end

local function sax_decode(sax, json, chunksize)
	local result
	local stack = {}
	local function add(v)
		local top = stack[#stack]
		if top then
			top[#top+1] = v
		else
			result = v
		end
	end
	local saxtbl = {
		startarray = function()
			local a = {}
			add(a)
			stack[#stack+1] = a
		end,
		endarray = function()
			stack[#stack] = nil
		end,
		number = add,
		string = add,
	}
	local i = 1
	local function gen()
		if i > #json then
			return nil
		end
		local s = string.sub(json, i, i+chunksize-1)
		i = i+chunksize
		return s
	end
	sax.newparser(gen, saxtbl).run()
	return result
end

local function same(a, b)
	if type(a) ~= type(b) then
		return false
	end
	if type(a) == 'table' then
		if #a ~= #b then
			return false
		end
		for i = 1, #a do
			if not same(a[i], b[i]) then
				return false
			end
		end
		return true
	end
	if math.type and math.type(a) ~= math.type(b) then
		return false
	end
	return a == b
end

local tests = {}

-- A failure in the middle of a surrogate pair must not affect the next call
-- of a decoder which is reused (as `lunajson.decode` is).
tests['surrogate state is reset after an error'] = function()
	local decode = require 'lunajson'.decode
	local bad = {
		'"' .. u'D840' .. u'ZZZZ' .. '"',  -- invalid hex after the 1st surrogate
		'"' .. u'D840' .. u'12' .. '"',    -- truncated escape after the 1st surrogate
	}
	for _, json in ipairs(bad) do
		if pcall(decode, json) then
			return 'not errored: ' .. json
		end
		local ok, err = pcall(decode, '"' .. u'DDA2' .. '"')
		if ok then
			return 'lone 2nd surrogate accepted after ' .. json
		end
		if not string.find(err, 'parse error at ', 1, true) then
			return string.format('%q', err)
		end
		ok, err = pcall(decode, '"\\n"')
		if not ok or err ~= '\n' then
			return 'valid string broken after ' .. json .. ': ' .. tostring(err)
		end
		ok, err = pcall(decode, '"' .. u'D840' .. u'DDA2' .. '"')
		if not ok or err ~= '\240\160\134\162' then
			return 'surrogate pair broken after ' .. json .. ': ' .. tostring(err)
		end
	end
end

-- Simulate a locale whose decimal mark is ',' (e.g. de_DE with Lua 5.1),
-- where tostring prints "0,5" and tonumber only accepts "1,5".
-- The modules capture these functions when loaded, so load fresh copies.
local function load_with_comma_locale(modname)
	local orig_tostring, orig_tonumber = tostring, tonumber
	local saved = package.loaded[modname]
	package.loaded[modname] = nil
	tostring = function(v)
		local s = orig_tostring(v)
		if type(v) == 'number' then
			s = string.gsub(s, '%.', ',')
		end
		return s
	end
	tonumber = function(s, base)
		if base == nil and type(s) == 'string' then
			if string.find(s, '.', 1, true) then
				return nil
			end
			s = string.gsub(s, ',', '.')
		end
		return orig_tonumber(s, base)
	end
	local ok, mod = pcall(require, modname)
	tostring, tonumber = orig_tostring, orig_tonumber
	package.loaded[modname] = saved
	if not ok then
		error(mod, 0)
	end
	return mod
end

local locale_json = '[1,15,1.5,-2.5e3,0.25,-0.5,10]'
local locale_ans = {1, 15, 1.5, -2.5e3, 0.25, -0.5, 10}

tests['decoder under a comma locale'] = function()
	local decode = load_with_comma_locale('lunajson.decoder')()
	local ok, v = pcall(decode, locale_json)
	if not ok then
		return string.format('%q', v)
	end
	if not same(v, locale_ans) then
		return 'wrong result'
	end
end

tests['sax under a comma locale'] = function()
	local sax = load_with_comma_locale('lunajson.sax')
	-- chunk size 1 exercises the fallback number parser
	for _, chunksize in ipairs({1, 3, 8192}) do
		local ok, v = pcall(sax_decode, sax, locale_json, chunksize)
		if not ok then
			return string.format('%q', v)
		end
		if not same(v, locale_ans) then
			return 'wrong result with chunk size ' .. chunksize
		end
	end
end

-- -0 must be decoded as float -0.0 even across chunk boundaries.
tests['sax keeps -0 across chunks'] = function()
	local sax = require 'lunajson.sax'
	for _, chunksize in ipairs({1, 2, 3, 8192}) do
		local v = sax_decode(sax, '[-0,-0,0]', chunksize)
		if not (v[1] == 0 and 1/v[1] < 0 and 1/v[2] < 0 and 1/v[3] > 0) then
			return 'sign of zero lost with chunk size ' .. chunksize
		end
		if math.type and math.type(v[1]) ~= 'float' then
			return '-0 is not float with chunk size ' .. chunksize
		end
	end
end

local names = {}
for name in pairs(tests) do
	names[#names+1] = name
end
table.sort(names)

local iserr = false
io.write('regression:\n')
for _, name in ipairs(names) do
	io.write('  ' .. name .. ': ')
	local ok, err = pcall(tests[name])
	if not ok then
		err = string.format('%q', err)
	end
	if err then
		iserr = true
		io.write(err .. '\n')
	else
		io.write('ok\n')
	end
end

return iserr
