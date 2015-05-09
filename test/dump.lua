local ipairs = ipairs
local pairs = pairs
local tostring = tostring
local type = type
local format = string.format
local huge = 1/0
local tiny = -1/0

local function dump(v)
	local builder = {}
	local i = 1

	local depth = 0
	local depth8 = 0
	local view = 1
	local usestack
	local vars = {'v1', 'v2', 'v3', 'v4', 'v5', 'v6', 'v7', 'v8', 'v1'}
	local vars2 = {'v1[', 'v2[', 'v3[', 'v4[', 'v5[', 'v6[', 'v7[', 'v8['}
	local var = 'v1'
	local nextvar = 'v1'
	local var2 = 'v1['
	local nextvar2 = 'v1['

	local function incdepth()
		depth = depth+1
		depth8 = depth8+1
		if depth8 > 8 then
			depth8 = 0
		end
		var = nextvar
		nextvar = vars[depth8+1]
		var2 = vars2[depth8]
		if depth >= view+8 then
			usestack = true
			view = view+1
			builder[i] = 'stack['
			builder[i+1] = depth-8
			builder[i+2] = ']='
			builder[i+3] = var
			builder[i+4] = '\n'
			i = i+5
		end
	end

	local function decdepth()
		depth = depth-1
		depth8 = depth8-1
		if depth8 < 1 then
			depth8 = 8
		end
		nextvar = var
		var = vars[depth8]
		nextvar2 = var2
		var2 = vars2[depth8]
		if depth < view and depth > 0 then
			view = view-1
			builder[i] = var
			builder[i+1] = '=stack['
			builder[i+2] = depth
			builder[i+3] = ']\n'
			i = i+4
		end
	end

	local visited = {}

	local tablefun, tbl

	local function tableelem(k, v)
		do
			local vt = type(v)
			if vt ~= 'table' then
				local e = tbl[vt](v)
				builder[i] = var2
				builder[i+1] = k
				builder[i+2] = ']='
				builder[i+3] = e
				builder[i+4] = '\n'
				i = i+5
				return
			end
		end
		do
			local olddepth = visited[v]
			if olddepth then
				builder[i] = var2
				builder[i+1] = k
				builder[i+2] = ']='
				if olddepth >= view then
					builder[i+3] = vars[olddepth%8]
				else
					builder[i+3] = 'stack['..olddepth..']'
				end
				builder[i+4] = '\n'
				i = i+5
				return
			end
		end
		do
			local oldvar2 = var2
			incdepth()
			visited[v] = depth
			if kt == nextvar then
				builder[i] = 'vtmp={}\n'
				builder[i+1] = oldvar2
				builder[i+2] = k
				builder[i+3] = ']=vtmp\n'
				builder[i+4] = var
				builder[i+5] = '=vtmp\n'
				i = i+6
			else
				builder[i] = var
				builder[i+1] = '={}\n'
				builder[i+2] = oldvar2
				builder[i+3] = k
				builder[i+4] = ']='
				builder[i+5] = var
				builder[i+6] = '\n'
				i = i+7
			end
		end
		tablefun(v)
		visited[v] = nil
		decdepth()
	end

	function tablefun(o)
		local l = 0
		for j, v in ipairs(o) do
			l = j
			tableelem(j, v)
		end
		for k, v in pairs(o) do
			local kt = type(k)
			if kt ~= 'number' or  k < 1 or k > l then
				k = tbl[kt](k)
				tableelem(k, v)
			end
		end
	end

	tbl = {
		boolean = tostring,
		table = function(o)
			do
				local olddepth = visited[o]
				if olddepth then
					if olddepth >= view then
						return vars[olddepth%8]
					else
						return 'stack['..olddepth..']'
					end
				end
			end
			incdepth()
			visited[o] = depth
			builder[i] = var
			builder[i+1] = '={}\n'
			i = i+2
			tablefun(o)
			visited[o] = nil
			decdepth()
			return nextvar
		end,
		string = function(s)
			return format('%q', s)
		end,
		number = function(n)
			if tiny < n and n < huge then
				return format('%.17g', n)
			elseif n == huge then
				return '1/0'
			elseif n == tiny then
				return '-1/0'
			else
				return '0/0'
			end
		end,
		__index = function(_)
			error("illegal val")
		end
	}
	setmetatable(tbl, tbl)

	builder[i] = 'local '
	i = i+1
	for j = 1, 8 do
		builder[i] = vars[j]
		builder[i+1] = ','
		i = i+2
	end
	builder[i] = 'vtmp\n'
	i = i+1
	local stackdecl = i
	builder[i] = ""
	i = i+1
	local e = tbl[type(v)](v)
	builder[i] = 'return '
	builder[i+1] = e
	i = i+2
	if usestack then
		builder[stackdecl] = 'local stack={}\n'
		i = i+1
	end

	return table.concat(builder)
end

return dump
