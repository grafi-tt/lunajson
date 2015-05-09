local oldcpath = package.cpath
package.cpath = ''
local dk = require 'dkjson'
package.cpath = oldcpath
local encode = dk.encode
local decode = function(json)
	local obj, msg = dk.decode(json)
	if obj == nil then
		error(msg)
	end
	return obj
end
return encode, decode
