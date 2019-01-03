return {
	load = function(fn)
		local path = arg[0]
		local dir = string.gsub(path, '/[^/]*$', '')
		local new_path = dir .. '/' .. fn
		arg[0] = new_path
		local arg_ = arg  -- workaround for Lua 5.1
		return (function (...)
			arg_[0] = path
			return ...
		end)(dofile(new_path))
	end,
	open = function(fn)
		local path = arg[0]
		local dir = string.gsub(path, '/[^/]*$', '')
		local new_path = dir .. '/' .. fn
		return io.open(new_path)
	end,
}
