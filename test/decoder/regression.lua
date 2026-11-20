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

-- Load a fresh copy of a module while some global functions are replaced,
-- as the modules capture them when loaded.
local function load_with(modname, globals)
	local saved_globals = {}
	for k, f in pairs(globals) do
		saved_globals[k] = _G[k]
		_G[k] = f
	end
	local saved = package.loaded[modname]
	package.loaded[modname] = nil
	local ok, mod = pcall(require, modname)
	for k, f in pairs(saved_globals) do
		_G[k] = f
	end
	package.loaded[modname] = saved
	if not ok then
		error(mod, 0)
	end
	return mod
end

-- Simulate a locale whose decimal mark is ',' (e.g. de_DE with Lua 5.1),
-- where tostring prints "0,5" and tonumber only accepts "1,5".
local function load_with_comma_locale(modname)
	local orig_tostring, orig_tonumber = tostring, tonumber
	return load_with(modname, {
		tostring = function(v)
			local s = orig_tostring(v)
			if type(v) == 'number' then
				s = string.gsub(s, '%.', ',')
			end
			return s
		end,
		tonumber = function(s, base)
			if base == nil and type(s) == 'string' then
				if string.find(s, '.', 1, true) then
					return nil
				end
				s = string.gsub(s, ',', '.')
			end
			return orig_tonumber(s, base)
		end,
	})
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

-- The key cache of a reused decoder must not keep keys of past calls alive.
tests['decoder does not retain keys across calls'] = function()
	local decode = require 'lunajson'.decode
	local pad = string.rep('x', 10)  -- short enough to be cached
	local function round(r)
		local parts = {}
		for k = 1, 1000 do
			parts[k] = '"' .. r .. '_' .. k .. pad .. '":1'
		end
		decode('{' .. table.concat(parts, ',') .. '}')
	end
	round(0)
	collectgarbage()
	collectgarbage()
	local base = collectgarbage('count')
	for r = 1, 50 do  -- 50000 unique keys, several MB if leaked
		round(r)
	end
	collectgarbage()
	collectgarbage()
	local grown = collectgarbage('count') - base
	if grown > 2048 then
		return string.format('%.1f KB retained', grown)
	end
end

-- A string spanning many chunks must be assembled in linear time.
-- Quadrupling the length should take about 4x time (quadratic: about 16x).
tests['sax assembles long strings in linear time'] = function()
	local sax = require 'lunajson.sax'
	local function run(n)
		local json = '"' .. string.rep('a', n) .. '"'
		local i = 1
		local function gen()  -- 1-byte chunks
			if i > #json then
				return nil
			end
			local s = string.sub(json, i, i)
			i = i+1
			return s
		end
		local got
		local t = os.clock()
		sax.newparser(gen, {string = function(s) got = s end}).run()
		t = os.clock() - t
		if got ~= string.sub(json, 2, -2) then
			error('wrong result')
		end
		return t
	end
	run(1000)  -- warm up
	local best = math.huge
	for _ = 1, 2 do  -- take the better one to reduce noise
		local ratio = run(400000) / math.max(run(100000), 1e-3)
		if ratio < best then
			best = ratio
		end
	end
	if best > 8 then
		return string.format('time grows superlinearly: 4x length took %.1fx time', best)
	end
end

-- Integers (Lua 5.3+) must be encoded exactly.
tests['encoder keeps integer precision'] = function()
	if not math.type then
		return  -- no integer subtype
	end
	local lj = require 'lunajson'
	local cases = {
		{9007199254740993, '9007199254740993'},
		{-9007199254740993, '-9007199254740993'},
		{math.maxinteger, tostring(math.maxinteger)},
		{math.mininteger, tostring(math.mininteger)},
		{0, '0'},
		{123, '123'},
	}
	for _, c in ipairs(cases) do
		local json = lj.encode(c[1])
		if json ~= c[2] then
			return 'encoded ' .. c[2] .. ' as ' .. json
		end
		local v = lj.decode(json)
		if v ~= c[1] or math.type(v) ~= 'integer' then
			return 'round trip of ' .. c[2] .. ' gave ' .. tostring(v)
		end
	end
	if lj.encode({1, 2.5, 9007199254740993}) ~= '[1,2.5,9007199254740993]' then
		return 'wrong array encoding: ' .. lj.encode({1, 2.5, 9007199254740993})
	end
end

-- a generator that returns chunks of the given sizes (cycled)
local function chunked(s, sizes)
	local i, k = 1, 0
	return function()
		if i > #s then
			return nil
		end
		k = k % #sizes + 1
		local c = string.sub(s, i, i + sizes[k] - 1)
		i = i + sizes[k]
		return c
	end
end

-- `read` must work with chunks of varying lengths, such as input from sockets,
-- or a file whose last chunk is shorter than the others.
tests['sax read with varying chunk sizes'] = function()
	local sax = require 'lunajson.sax'
	local data = string.rep('0123456789', 3000)  -- 30000 bytes
	local src = data .. '[1]'
	local patterns = {{4}, {3, 5}, {2, 7}, {1, 3}, {5, 1, 1}, {8192, 3}}
	local reads = {10, 1, 0, 7, 25, 8192, 3, 13000}  -- in total 29248 bytes
	for _, sizes in ipairs(patterns) do
		local p = sax.newparser(chunked(src, sizes), {})
		local pos = 1
		local label = 'chunk sizes ' .. table.concat(sizes, ',')
		for _, n in ipairs(reads) do
			local s = p.read(n)
			if s ~= string.sub(data, pos, pos + n - 1) then
				return string.format('%s: read(%d) at %d returned %d bytes', label, n, pos, #s)
			end
			pos = pos + n
			if p.tellpos() ~= pos then
				return string.format('%s: tellpos %d, expected %d', label, p.tellpos(), pos)
			end
		end
		local rest = p.read(#data - pos + 1)  -- up to just before '[1]'
		if rest ~= string.sub(data, pos) then
			return label .. ': the last read returned wrong bytes'
		end
		-- the JSON value after the raw bytes must be parsed correctly
		local got
		local ok, err = pcall(function()
			local q = sax.newparser(chunked(src, sizes), {number = function(n) got = n end})
			q.read(#data)
			q.run()
		end)
		if not ok then
			return label .. ': ' .. tostring(err)
		end
		if got ~= 1 then
			return label .. ': value after read is wrong'
		end
	end
end

-- In a stream of values, a number may be directly followed by '[' or '{'.
-- The result must not depend on where chunks are split.
tests['sax number followed by bracket at chunk boundary'] = function()
	local sax = require 'lunajson.sax'
	local cases = {
		{'1[2]', 1, '[', 2},
		{'1{}', 1, '{'},
		{'0[2]', 0, '[', 2},
		{'-1[2]', -1, '[', 2},
		{'1.5[2]', 1.5, '[', 2},
		{'1e2{}', 100, '{'},
	}
	for _, c in ipairs(cases) do
		for _, size in ipairs({1, 2, 3, 100}) do
			local nums = {}
			local p = sax.newparser(chunked(c[1], {size}), {number = function(n) nums[#nums+1] = n end})
			local ok, err = pcall(function()
				p.run()
				if p.tryc() ~= string.byte(c[3]) then
					error('next byte is not ' .. c[3])
				end
				p.run()
			end)
			if not ok then
				return string.format('%s with chunk size %d: %s', c[1], size, tostring(err))
			end
			if nums[1] ~= c[2] or nums[2] ~= c[4] then
				return string.format('%s with chunk size %d: wrong values', c[1], size)
			end
		end
	end
	-- letters directly after a number are still errors
	for _, json in ipairs({'1Z', '1z', '1A', '1a'}) do
		for _, size in ipairs({1, 100}) do
			if pcall(sax.newparser(chunked(json, {size}), {}).run) then
				return json .. ' accepted with chunk size ' .. size
			end
		end
	end
end

-- `tellpos` must be consistent between string and function sources,
-- also after reading past the end of the input.
tests['sax tellpos after reading past the end'] = function()
	local sax = require 'lunajson.sax'
	local function sources(s)
		return {
			string = function() return s end,
			whole = function() local d = s return function() local r = d d = nil return r end end,
			bytes = function() return chunked(s, {1}) end,
		}
	end
	-- each case: a sequence of operations and the expected results
	local cases = {
		{{'read', 10, 'abc'}, {'tellpos', 4}},
		{{'read', 2, 'ab'}, {'read', 5, 'c'}, {'tellpos', 4}},
		{{'read', 3, 'abc'}, {'tellpos', 4}, {'read', 1, ''}, {'tellpos', 4}},
		{{'read', 4, 'abc'}, {'tryc', nil}, {'tellpos', 4}},
		{{'tryc', 0x61}, {'read', 100, 'abc'}, {'tellpos', 4}, {'read', 0, ''}, {'tellpos', 4}},
	}
	for name, mk in pairs(sources('abc')) do
		for k, case in ipairs(cases) do
			local p = sax.newparser(mk(), {})
			for _, op in ipairs(case) do
				local got
				if op[1] == 'read' then
					got = p.read(op[2])
					if got ~= op[3] then
						return string.format('%s source, case %d: read(%d) gave %q', name, k, op[2], got)
					end
				elseif op[1] == 'tryc' then
					got = p.tryc()
					if got ~= op[2] then
						return string.format('%s source, case %d: tryc gave %s', name, k, tostring(got))
					end
				else
					got = p.tellpos()
					if got ~= op[2] then
						return string.format('%s source, case %d: tellpos %d, expected %d', name, k, got, op[2])
					end
				end
			end
		end
	end
	-- after a value at the end of a string source
	local p = sax.newparser('[1] ', {})
	p.run()
	p.read(5)
	if p.tellpos() ~= 5 then
		return 'tellpos after run and read: ' .. p.tellpos()
	end
end

-- An array length given by [0] must not produce invalid JSON.
tests['encoder with fractional array length'] = function()
	local encode = require 'lunajson'.encode
	local cases = {
		{{[0] = 0}, '[]'},
		{{[0] = 0.5}, '[]'},
		{{[0] = -1}, '[]'},
		{{[0] = 1, 'a'}, '["a"]'},
		{{[0] = 1.5, 'a', 'b'}, '["a"]'},
		{{[0] = 2, 'a'}, '["a",null]'},
	}
	for _, c in ipairs(cases) do
		local json = encode(c[1])
		if json ~= c[2] then
			return string.format('[0]=%s gave %s, expected %s', tostring(c[1][0]), json, c[2])
		end
	end
end

-- Without `pos`, nothing but spaces may follow the value.
tests['decoder rejects trailing garbage'] = function()
	local decode = require 'lunajson'.decode
	for _, json in ipairs({'[1]x', '{}}', '[][]', '1 2', '"a"b', '[1]]', 'nulll', 'truex', '0 0'}) do
		local ok, err = pcall(decode, json)
		if ok then
			return 'not errored: ' .. json
		end
		if not string.find(err, 'parse error at ', 1, true) then
			return string.format('%q', err)
		end
	end
	for _, json in ipairs({'[1] ', '[1]\n\t\r ', ' 1 '}) do
		local ok, err = pcall(decode, json)
		if not ok then
			return string.format('%q', err)
		end
	end
end

-- Lua 5.3.0-5.3.2 wrap decimal integers that overflow instead of converting
-- them to floats. Test with the real tonumber, and with one that wraps
-- around like those versions.
if math.type then
	local orig_tonumber = tonumber
	local function wrapping_tonumber(s, base)
		if base == nil and type(s) == 'string' and string.find(s, '^%-?[0-9]+$') then
			local a = 0
			for d in string.gmatch(s, '[0-9]') do
				a = a * 10 + (string.byte(d) - 48)  -- integer arithmetic wraps around
			end
			if string.sub(s, 1, 1) == '-' then
				a = -a
			end
			return a
		end
		return orig_tonumber(s, base)
	end

	local json = '[18446744073709551617,9223372036854775808,-9223372036854775808,' ..
		'9223372036854775807,-9223372036854775807,-18446744073709551616,' ..
		'12345678901234567890123,1234567890123456789,10]'
	local ans = {
		18446744073709551617.0, 9223372036854775808.0, math.mininteger,
		math.maxinteger, -math.maxinteger, -18446744073709551616.0,
		12345678901234567890123.0, 1234567890123456789, 10
	}

	tests['big integers are not wrapped around'] = function()
		for _, tn in ipairs({orig_tonumber, wrapping_tonumber}) do
			local kind = tn == orig_tonumber and 'tonumber' or 'wrapping tonumber'
			if wrapping_tonumber('18446744073709551617') ~= 1 then
				return 'wrapping tonumber is broken'
			end
			local decode = load_with('lunajson.decoder', {tonumber = tn})()
			local ok, v = pcall(decode, json)
			if not ok then
				return kind .. ': ' .. string.format('%q', v)
			end
			if not same(v, ans) then
				return kind .. ': decoder gave a wrong result'
			end
			local sax = load_with('lunajson.sax', {tonumber = tn})
			-- chunk size 1 exercises the fallback number parser
			for _, chunksize in ipairs({1, 8192}) do
				ok, v = pcall(sax_decode, sax, json, chunksize)
				if not ok then
					return kind .. ': ' .. string.format('%q', v)
				end
				if not same(v, ans) then
					return kind .. ': sax gave a wrong result with chunk size ' .. chunksize
				end
			end
		end
	end
end

-- The decoder and the encoder must not keep the last input/output (which can
-- be huge) alive until the next call, either after success or after an error.
local function find_upvalues(f, names)
	local found = {}
	local i = 1
	while true do
		local name, value = debug.getupvalue(f, i)
		if not name then
			break
		end
		if names[name] then
			found[name] = true
			if value ~= nil then
				return name .. ' is kept'
			end
		end
		i = i+1
	end
	for name in pairs(names) do
		if not found[name] then
			return 'upvalue ' .. name .. ' not found'
		end
	end
end

tests['decoder does not keep the last input'] = function()
	local decode = require 'lunajson.decoder'()
	local names = {json = true, nullv = true}
	local null = {}
	for _, call in ipairs({
		{'[1,null]', nil, null}, {'[1] ', 1, null}, {'[1,', nil, null}, {'[1]x', nil, null},
		{'"' .. u'D840' .. '"', nil, null}, {'[1.]', 1, null},
	}) do
		pcall(decode, call[1], call[2], call[3])
		local err = find_upvalues(decode, names)
		if err then
			return err .. ' after decoding ' .. call[1]
		end
	end
end

tests['encoder does not keep the last value'] = function()
	local encode = require 'lunajson.encoder'()
	local names = {v = true, nullv = true, builder = true, visited = true}
	local loop = {}
	loop[1] = loop
	for _, v in ipairs({{1, 'a', {x = 0.5}}, {0/0}, {print}, loop, {[true] = 1}}) do
		pcall(encode, v, {})
		local err = find_upvalues(encode, names)
		if err then
			return err
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
