#!/bin/sh
source ./luabin.sh

echo "# valid"
for l in *-decoder.lua; do
	echo "## $l"
	for j in validjson/*.json; do
		echo "### ${j}"
		echo "#### lua51"
		eval "${lua51}" test.lua valid "${l}" "${j}"
		echo "#### lua52"
		eval "${lua52}" test.lua valid "${l}" "${j}"
		echo "#### luajit"
		eval "${luajit}" test.lua valid "${l}" "${j}"
	done
done

echo "# invalid"
for l in *-decoder.lua; do
	echo "## $l"
	for j in invalidjson/*.json; do
		echo "### ${j}"
		echo "#### lua51"
		eval "${lua51}" test.lua invalid "${l}" "${j}"
		echo "#### lua52"
		eval "${lua52}" test.lua invalid "${l}" "${j}"
		echo "#### luajit"
		eval "${luajit}" test.lua invalid "${l}" "${j}"
	done
done

echo "# bench"
cd benchjson
for r in *.rb; do
	ruby "${r}" > "${r%.rb}.json"
done
cd ..
for l in *-decoder.lua; do
	echo "## $l"
	for j in benchjson/*.json; do
		echo "### ${j}"
		echo "#### lua51"
		eval "${lua51}" test.lua bench "${l}" "${j}"
		echo "#### lua52"
		eval "${lua52}" test.lua bench "${l}" "${j}"
		echo "#### luajit"
		eval "${luajit}" test.lua bench "${l}" "${j}"
	done
done
cd benchjson
for r in *.rb; do
	rm "${r%.rb}.json"
done
cd ..
