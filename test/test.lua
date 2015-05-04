local function isomorphic(u, v)
	local s = type(u)
	local t = type(v)
	if s ~= t then
			error('different values: ' .. tostring(s) .. ' and ' .. tostring(t))
	else
		if s == 'table' then
			local ukeys = {}
			for k, _ in pairs(u) do
				table.insert(ukeys, k)
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
					error('different keys: ' .. j .. ' and ' .. k)
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
	lunasax = require 'sax-decode'
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
