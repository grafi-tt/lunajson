local util = require('util')


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
	local v = decode(json, nullv)

	local ans = util.load(fn .. '.lua')
	isomorphic(ans, v)
end

local function test_invalid(decode, fn)
	local fp = util.open(fn .. '.json')
	local json = fp:read('*a')
	fp:close()

	if pcall(decode, json, nullv) then
		error("not errored")
	end
end


local decoders = util.load('decoders.lua')
local valid_data = util.load('valid_data.lua')
local invalid_data = util.load('invalid_data.lua')

for _, decoder in ipairs(decoders) do
	print(decoder .. ':')
	local decode = util.load('decode/' .. decoder .. '.lua')
	for _, fn in ipairs(valid_data) do
		print('  ' .. fn)
		fn = 'valid_data/' .. fn
		test_valid(decode, fn)
	end
	for _, fn in ipairs(invalid_data) do
		print('  ' .. fn)
		fn = 'invalid_data/' .. fn
		test_invalid(decode, fn)
	end
end
