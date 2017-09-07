local lj = require 'lunajson'
local util = require 'util'


local function test(round)
	local saxtbl = {}
	local bufsize = round == 1 and 64 or 1

	local fp = util.open('test.dat')
	local function input()
		local s = fp:read(bufsize)
		if not s then
			fp:close()
			fp = nil
		end
		return s
	end
	local parser = lj.newparser(input, saxtbl)

	if (parser.tryc() ~= string.byte('a')) then
		print(parser.tryc())
		return "1st not a"
	end
	if (parser.read(3) ~= ("abc")) then
		return "not abc"
	end
	if (parser.read(75) ~= ("abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabc")) then
		return "not abc*25"
	end
	if (parser.tellpos() ~= 79) then
		return "not read 78"
	end
	parser.run()
	if parser.tellpos() ~= 139 then
		return "1st json not end at 139"
	end
    if parser.read(8) ~= "  mmmmmm" then
		return "not __mmmmmm"
	end
	parser.run()
	if parser.tryc() ~= string.byte('&') then
		return "not &"
	end
	if parser.read(200) ~= '&++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++' then
		return "not &+*"
	end
	if parser.tellpos() ~= 276 then
		print(parser.tellpos())
		return "not last pos"
	end
	if parser.tryc() then
		return "not ended"
	end
	if parser.read(10) ~= ""  then
		return "not empty"
	end
	if parser.tellpos() ~= 276 then
		return "last pos moving"
	end
end


io.write('parse: ')
for round = 1, 2 do
	local err = test(round)
	if err then
		io.write(err .. '\n')
		return true
	else
		io.write('ok\n')
		return false
	end
end
