local oldcpath = package.cpath
package.cpath = ''
local dk = require 'dkjson'
package.cpath = oldcpath
return function(json, nv)
	local obj, msg = dk.decode(json, 1, nv)
	if obj == nil then
		error(msg)
	end
	return obj
end
