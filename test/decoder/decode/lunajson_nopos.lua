local lj = require 'lunajson'
-- without `pos`, the decoder also checks that nothing follows the value
return function(json, nv)
	return lj.decode(json, nil, nv)
end
