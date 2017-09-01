#!/bin/sh

. "${0%/*}/../ci/lua_impls.sh"


err=0
for lua_impl in $lua_impls; do
	set_lua_vars
	echo "---"
	echo "lua_impl: ${lua_impl}"
	"${lua_base}/${lua_bin}" "${0%/*}/test.lua" || err=1
done

exit $err
