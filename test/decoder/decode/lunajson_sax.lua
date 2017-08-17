local sax_decoder = require 'sax_decoder'

return function(json, nv)
	local i = 1
	local function gen()
		local s = string.sub(json, i, i+8191)
		i = i+8192
		if string.len(s) == 0 then
			s = nil
		end
		return s
	end
	return sax_decoder(gen, nv)
end
