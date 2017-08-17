#!/bin/sh

. "${0%/*}/../ci/lua_dists.sh"

for lua_dist in $lua_dists; do
	set_lua_vars
	"$lua_bin" "${0%/*}/bench.lua"
done
