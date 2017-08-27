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
		return '"incorrect encoding result"'
	end
end

function test_invalid(encode, fn)
	local data = util.load(fn .. '.lua')
	local ok, err = pcall(encode, data)
	if ok then
		return '"not errored"'
	end
end


local encoders = util.load('encoders.lua')
local valid_data = util.load('valid_data.lua')
local invalid_data = util.load('invalid_data.lua')

local iserr = false
io.write('encode:\n')
for _, encoder in ipairs(encoders) do
	io.write('  ' .. encoder .. ':\n')
	local encode = util.load('encode/' .. encoder .. '.lua')
	for _, fn in ipairs(valid_data) do
		io.write('    ' .. fn .. ': ')
		fn = 'valid_data/' .. fn
		local err = test_valid(encode, fn)
		if err then
			iserr = true
			io.write(err .. '\n')
		else
			io.write('ok\n')
		end
	end
	for _, fn in ipairs(invalid_data) do
		io.write('    ' .. fn .. ': ')
		fn = 'invalid_data/' .. fn
		local err = test_invalid(encode, fn)
		if err then
			iserr = true
			io.write(err .. '\n')
		else
			io.write('ok\n')
		end
	end
end

return iserr
