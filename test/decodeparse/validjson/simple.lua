local a = {}
for i = 0, 9999 do
	local f = i-0.0
	local vs = {true, "foo\nbar", i}
	a[i+1] = {
		x = 9*f+f/100000,
		y = -f+f/100000,
		string = string.format("mmm%xaaaaaaaa", i%1000),
		value = vs[i%3+1],
	}
end
a[10001] = false
return a
