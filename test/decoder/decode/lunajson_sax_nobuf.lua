local sax_decoder = require 'sax_decoder'

return function(json, nv)
	local i = 1
	local j = 0
	local function gen()
		local s = string.sub(json, i, i+j)
		j = j+1
		i = i+j
		if j == 4 then
			j = 0
		end
		if string.len(s) == 0 then
			s = nil
		end
		return s
	end
	return sax_decoder(gen, nv)
end
