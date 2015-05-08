require 'luapath'

local task = arg[1]
local decoderfile = arg[2]
local jsonfile = arg[3]

local jfp = io.open(jsonfile)
local json = jfp:read('*a')
jfp:close()

local decode = dofile(decoderfile)
local nullv = 1/0

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

tasks = {
	valid = function()
		local answerfile = string.gsub(jsonfile, '%.json$', '.lua')
		local lfp = io.open(answerfile)
		local ans = dofile(answerfile)
		lfp:close()
		local v = decode(json, nullv)
		isomorphic(ans, v)
	end
}

tasks[task]()
