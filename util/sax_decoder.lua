local lj = require 'lunajson'

return function(gen, nv)
	local saxtbl = {}
	local current = {}
	do
		local stack = {}
		local top = 1
		local key = 1

		local function add(v)
			if v == nil then
				v = nv
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
		saxtbl.number = add
		saxtbl.boolean = add
		saxtbl.null = add
	end

	lj.newparser(gen, saxtbl).run()
	return current[1]
end
