#!/bin/sh

. "${0%/*}/lua_dists.sh"


build_lua() {
	rm -rf "$lua_dist"
	tar xzf "$lua_archive" || exit $?
	cd "$lua_dist"
	case "$lua_dist" in
		lua-* ) make "$platform" || exit $?;;
		LuaJIT-* ) make || exit $?;;
	esac
	cd ..
}


mkdir -p "$lua_base"
cd "$lua_base"

for lua_dist in $lua_dists; do
	set_lua_vars
	[ -e "$lua_archive" ] || wget "$lua_url" || exit $?
	[ -e "$lua_bin" ] || build_lua || exit $?
done
