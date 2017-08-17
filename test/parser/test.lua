local lj = require 'lunajson'
local util = require 'util'


local saxtbl = {}

for round = 1, 2 do
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
		error("1st not a")
	end
	if (parser.read(3) ~= ("abc")) then
		error("not abc")
	end
	if (parser.read(75) ~= ("abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabc")) then
		error("not abc*25")
	end
	if (parser.tellpos() ~= 79) then
		error("not read 78")
	end
	parser.run()
	if parser.tellpos() ~= 139 then
		error("1st json not end at 139")
	end
    if parser.read(8) ~= "  mmmmmm" then
		error("not __mmmmmm")
	end
	parser.run()
	if parser.tryc() ~= string.byte('+') then
		error("not +")
	end
	if parser.read(200) ~= '+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++' then
		error("not +*")
	end
	if parser.tellpos() ~= 276 then
		print(parser.tellpos())
		error("not last pos")
	end
	if parser.tryc() then
		error("not ended")
	end
	if parser.read(10) ~= ""  then
		error("not empty")
	end
	if parser.tellpos() ~= 276 then
		error("last pos moving")
	end
end
