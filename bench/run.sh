#!/bin/sh

. "${0%/*}/../ci/lua_impls.sh"


for lua_impl in $lua_impls; do
	set_lua_vars
	echo "---"
	echo "lua_impl: ${lua_impl}"
	"${lua_base}/$lua_bin" "${0%/*}/bench.lua"
done
