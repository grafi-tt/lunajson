local ln = require 'lunajson'
return function(json, nv)
	local v, pos = ln.decode(json, 1, nv)
	return v
end
