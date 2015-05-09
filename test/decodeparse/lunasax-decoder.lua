local saxtbl = {}
local current = {}
local nullv

do
	local stack = {}
	local top = 1

	local key = 1
	local isobj

	local function add(v)
		if v == nil then
			v = nullv
		end
		current[key] = v
		if type(key) == 'number' then
			key = key+1
		end
	end
	local function push()
		stack[top] = current
		stack[top+1] = key
		top = top+2
	end
	local function pop()
		top = top-2
		key = stack[top+1]
		current = stack[top]
	end

	function saxtbl.startobject()
		push()
		current = {}
		key = nil
	end
	function saxtbl.key(s)
		key = s
	end
	function saxtbl.endobject()
		local obj = current
		pop()
		add(obj)
	end
	function saxtbl.startarray()
		push()
		current = {}
		key = 1
	end
	function saxtbl.endarray()
		local ary = current
		pop()
		add(ary)
	end
	saxtbl.string = add
	saxtbl.number = function(n)
		current[key] = n-0.0
		if type(key) == 'number' then
			key = key+1
		end
	end
	saxtbl.boolean = add
	saxtbl.null = add
end

return function(json, nv)
	nullv = nv
	local lunajson = require 'lunajson'
	local i = 1
	local function gen()
		local s = string.sub(json, i, i+8191)
		i = i+8192
		if string.len(s) == 0 then
			s = nil
		end
		return s
	end
	lunajson.newparser(gen, saxtbl).run()
	return current[1]
end
