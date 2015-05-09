local a = {}
for i = 1, 100000 do
	local f = i-1.0
	local vs = {true, "foo\nbar"}
	a[i] = {
		x = f+f/1000000,
		y = -f+f/1000000,
		aaaaaaaa = vs[i%2]
	}
end
return a
