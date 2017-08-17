local lj = require 'lunajson'
return function(json, nv)
	local v, pos = lj.decode(json, 1, nv)
	return v
end
