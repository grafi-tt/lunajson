local lj = require 'lunajson'


-- Ordered table support
--   keylist[metafirstkey] = firstkey
--   keylist[key] = nextkey
--   keylist[lastkey] = nil
local metafirstkey = {}
local function orderedtable(obj)
	local keylist = {}
	local lastkey = metafirstkey
	local function onext(key2val, key)
		local val
		repeat
			key = keylist[key]
			if key == nil then
				return
			end
			val = key2val[key]
		until val ~= nil
		return key, val
	end
	local metatable = {
		__newindex = function(key2val, key, val)
			rawset(key2val, key, val)
			-- do the assignment first in case key == lastkey
			keylist[lastkey] = key
			if keylist[key] == nil then
				lastkey = key
			else
				keylist[lastkey] = nil
			end
		end,
		__pairs = function(key2val)
			return onext, key2val, metafirstkey
		end
	}
	return setmetatable(obj, metatable)
end


return function(gen, nv, preserveorder)
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
			if preserveorder then
				current = orderedtable(current)
			end
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
