#!/bin/sh
source ../luabin.sh

echo "# valid"
for l in all-*-encoder.lua; do
	echo "## $l"
	for d in validdata/*.lua; do
		echo "### ${d}"
		echo "#### lua51"
		eval "${lua51}" test.lua valid "${l}" "${d}" 2>&1
		echo "#### lua52"
		eval "${lua52}" test.lua valid "${l}" "${d}" 2>&1
		echo "#### lua53"
		eval "${lua53}" test.lua valid "${l}" "${d}" 2>&1
		echo "#### luajit"
		eval "${luajit}" test.lua valid "${l}" "${d}" 2>&1
	done
done

echo "# bench"
for d in benchdata/*.lua; do
	echo "## ${j}"
	for lua in lua51 lua52 lua53 luajit; do
		echo "### ${lua}"
		for l in all-*-encoder.lua bench-*-encoder.lua; do
			echo "#### $l"
			eval luaexec="\$${lua}"
			eval "${luaexec}" test.lua bench "${l}" "${d}" 2>&1
		done
	done
done
