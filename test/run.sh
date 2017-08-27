#!/bin/sh

. "${0%/*}/../ci/lua_dists.sh"


err=0
for lua_dist in $lua_dists; do
	set_lua_vars
	echo "---"
	echo "# ${lua_dist}"
	"${lua_base}/${lua_bin}" "${0%/*}/test.lua" || err=1
done

exit $err
