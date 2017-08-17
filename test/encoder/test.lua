local util = require 'util'


function test_valid(encode, fn)
	local data = util.load(fn .. '.lua')
	local json = encode(data)
	local ans_fp = util.open(fn ..  '.json')
	local ok = false
	for l in ans_fp:lines() do
		ok = ok or json == l
	end
	ans_fp:close()
	if not ok then
		error("incorrect encoding result")
	end
end

function test_invalid(encode, fn)
	local data = util.load(fn .. '.lua')
	local iserr = false
	local origerror = error
	error = function()
		iserr = true
		origerror()
	end
	pcall(encode, data)
	error = origerror
	if not iserr then
		error("not errored")
	end
end


local encoders = util.load('encoders.lua')
local valid_data = util.load('valid_data.lua')
local invalid_data = util.load('invalid_data.lua')

for _, encoder in ipairs(encoders) do
	print(encoder .. ':')
	local encode = util.load('encode/' .. encoder .. '.lua')
	for _, fn in ipairs(valid_data) do
		print('  ' .. fn)
		fn = 'valid_data/' .. fn
		test_valid(encode, fn)
	end
	for _, fn in ipairs(invalid_data) do
		print('  ' .. fn)
		fn = 'invalid_data/' .. fn
		test_invalid(encode, fn)
	end
end
