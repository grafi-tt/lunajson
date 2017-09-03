local error, pairs, setmetatable, tonumber, tostring, type =
      error, pairs, setmetatable, tonumber, tostring, type
local mtype = math.type or function(n) return 'float' end
local find, format =
      string.find, string.format
local concat = table.concat

_ENV = nil


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
			depth8 = 1
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

		local olddepth = visited[v]
		if olddepth then
			builder[i] = var2
			builder[i+1] = k
			builder[i+2] = ']='
			if olddepth >= view then
				builder[i+3] = vars[(olddepth-1)%8+1]
			else
				builder[i+3] = 'stack['..olddepth..']'
			end
			builder[i+4] = '\n'
			i = i+5
			return
		end

		local oldvar2 = var2
		incdepth()
		visited[v] = depth
		builder[i] = var
		builder[i+1] = '={}\n'
		builder[i+2] = oldvar2
		builder[i+3] = k
		builder[i+4] = ']='
		builder[i+5] = var
		builder[i+6] = '\n'
		i = i+7
		tablefun(v)
		visited[v] = nil
		decdepth()
	end

	function tablefun(o)
		for k, v in pairs(o) do
			k = tbl[type(k)](k)
			tableelem(k, v)
		end
	end

	tbl = {
		boolean = tostring,
		table = function(o)
			do
				local olddepth = visited[o]
				if olddepth then
					if olddepth >= view then
						return vars[(olddepth-1)%8+1]
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
				if mtype(n) == 'float' then
					n = format('%.17g', n)
					if not find(n, '[^-0-9]') then
						n = n .. '.0'
					end
					return n
				else
					return tonumber(n)
				end
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
		if j < 8 then
			builder[i+1] = ','
		else
			builder[i+1] = '\n'
		end
		i = i+2
	end
	local stackdecl = i
	builder[i] = ""
	i = i+1
	local e = tbl[type(v)](v)
	builder[i] = 'return '
	builder[i+1] = e
	i = i+2
	if usestack then
		builder[stackdecl] = 'local stack={}\n'
	end

	return concat(builder)
end

return dump
