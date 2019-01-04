return setmetatable({a=1, b=2, c=3, d=4, e=5, j=10, i=9, h=8, g=7, f=6}, {
	__pairs = function()
		local function nxt(_, k)
			if k == nil then return 'a', 1 end
			if k == 'a' then return 'b', 2 end
			if k == 'b' then return 'c', 3 end
			if k == 'c' then return 'd', 4 end
			if k == 'd' then return 'e', 5 end
			if k == 'e' then return 'j', 10 end
			if k == 'j' then return 'i', 9 end
			if k == 'i' then return 'h', 8 end
			if k == 'h' then return 'g', 7 end
			if k == 'g' then return 'f', 6 end
		end
		return nxt, nil, nil
	end
})
