#!/bin/sh

. "${0%/*}/lua_impls.sh"


build_lua() {
	rm -rf "$lua_impl"
	tar xzf "$lua_archive" || exit $?
	cd "$lua_impl"
	case "$lua_impl" in
		lua-* ) make "$platform" || exit $?;;
		LuaJIT-* ) make || exit $?;;
	esac
	cd ..
}


mkdir -p "$lua_base"
cd "$lua_base"

for lua_impl in $lua_impls; do
	set_lua_vars
	[ -e "$lua_archive" ] || wget "$lua_url" || exit $?
	[ -e "$lua_bin" ] || build_lua || exit $?
done
