local util = require 'util'


local function isomorphic(u, v)
	local s = type(u)
	local t = type(v)
	if s ~= t then
		error('different values: ' .. tostring(s) .. ' and ' .. tostring(t))
	else
		if s == 'table' then
			local ukeys = {}
			for j, _ in pairs(u) do
				table.insert(ukeys, j)
			end
			table.sort(ukeys)
			local vkeys = {}
			for k, _ in pairs(v) do
				table.insert(vkeys, k)
			end
			table.sort(vkeys)
			local i = 1
			repeat
				local j = ukeys[i]
				local k = vkeys[i]
				if j ~= k then
					if v[j] == nil then
						error('only left-hand has the key: ' .. j)
					end
					if u[k] == nil then
						error('only right-hand has the key: ' .. k)
					end
				end
				if not j then
					break
				end
				i = i+1
				isomorphic(u[j], v[k])
			until false
		else
			if math.type then
				s = math.type(u)
				t = math.type(v)
				if s ~= t then
					error('different values: ' .. tostring(s) .. tostring(u) .. ' and ' .. tostring(t) .. tostring(v))

				end
			end
			if u ~= v then
				error('different values: ' .. tostring(u) .. ' and ' .. tostring(v))
			end
		end
	end
end


local nullv = 1/0

local function test_valid(decode, fn)
	local fp = util.open(fn .. '.json')
	local json = fp:read('*a')
	fp:close()

	local function check()
		local v = decode(json, nullv)
		local ans = util.load(fn .. '.lua')
		isomorphic(v, ans)
	end
	local ok, err = pcall(check)
	if not ok then
		return string.format('%q', err)
	end
end

local function test_invalid(decode, fn)
	local fp = util.open(fn .. '.json')
	local json = fp:read('*a')
	fp:close()

	local ok, err = pcall(decode, json, nullv)
	if ok then
		return '"not errored"'
	end
	if not string.find(err, "parse error at ", 1, true) then
		return string.format('%q', err)
	end
end


local decoders = util.load('decoders.lua')
local valid_data = util.load('valid_data.lua')
local invalid_data = util.load('invalid_data.lua')

local iserr = false
io.write('decode:\n')
for _, decoder in ipairs(decoders) do
	io.write('  ' .. decoder .. ':\n')
	local decode = util.load('decode/' .. decoder .. '.lua')
	for _, fn in ipairs(valid_data) do
		io.write('    ' .. fn .. ': ')
		fn = 'valid_data/' .. fn
		local err = test_valid(decode, fn)
		if err then
			iserr = true
			io.write(err .. '\n')
		else
			io.write('ok\n')
		end
	end
	for _, fn in ipairs(invalid_data) do
		io.write('    ' .. fn  .. ': ')
		fn = 'invalid_data/' .. fn
		test_invalid(decode, fn)
		local err = test_invalid(decode, fn)
		if err then
			iserr = true
			io.write(err .. '\n')
		else
			io.write('ok\n')
		end
	end
end

return iserr
