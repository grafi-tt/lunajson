local util = require 'util'
local iserr = false

iserr = util.load('decoder/test.lua') or iserr
iserr = util.load('encoder/test.lua') or iserr
iserr = util.load('parser/test.lua') or iserr

if iserr then
	os.exit(1)
end
