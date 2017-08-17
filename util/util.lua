return {
	load = function(fn)
		local path = arg[0]
		local dir = string.gsub(path, '/[^/]*$', '')
		local new_path = dir .. '/' .. fn
		arg[0] = new_path
		local v = dofile(new_path)
		arg[0] = path
		return v
	end,
	open = function(fn)
		local path = arg[0]
		local dir = string.gsub(path, '/[^/]*$', '')
		local new_path = dir .. '/' .. fn
		return io.open(new_path)
	end,
}
