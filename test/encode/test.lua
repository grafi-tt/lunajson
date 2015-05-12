local task = arg[1]
local encoderfile = arg[2]
local datafile = arg[3]

local data = dofile(datafile)

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
		local encode, decode = dofile(encoderfile)
		local j = encode(data)
		local v = decode(j)
		isomorphic(data, v)
	end,
	invalid = function()
		local iserr
		local origerror = error
		error = function()
			iserr = true
			origerror()
		end
		local encode = dofile(encoderfile)
		pcall(encode, data)
		error = origerror
		if not iserr then
			error("not errored")
		end
	end,
	bench = function()
		local acc = 0
		local encode = dofile(encoderfile)
		for i = 1, 100 do
			local t1 = os.clock()
			encode(data)
			local t2 = os.clock()
			local t = t2-t1
			--print(string.format("%2d: %.03fsec", i, t))
			acc = acc+t
		end
		print(string.format("%.03fsec", acc))
	end,
}

tasks[task]()
