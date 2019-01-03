local lj = require 'lunajson'
return function(json, nv, preserveorder)
	local v, pos = lj.decode(json, 1, nv, false, preserveorder)
	return v
end
