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

cd benchjson
for r in *.rb; do
	ruby "${r}" > "${r%.rb}.json"
done
for r in *.rb; do
	rm "${r%.rb}.json"
done
