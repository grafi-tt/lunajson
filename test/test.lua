package.path = '../src/?.lua;' .. package.path

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

local str = io.stdin:read('*a')
local decoders = {
	dkjson = function(json, nv)
		local dk = require 'dkjson'
		local obj, msg = dk.decode(json, 1, nv)
		if obj == nil then
			error(msg)
		end
		return obj
	end,
	lunasax = require 'sax-decode',
	lunasimple = function(json, nv)
		local dec = require 'lunajson.decode'
		local v, pos = dec(json, 1, nv)
		return v
	end,
}
local nullv = function() end

local results = {}
for name, decode in pairs(decoders) do
	print(name)
	local t1 = os.clock()
	table.insert(results, decode(str, nullv))
	local t2 = os.clock()
	print(t2-t1)
end

isomorphic(results[1], results[2])
isomorphic(results[1], results[3])
