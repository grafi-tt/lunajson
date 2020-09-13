#!/bin/sh

. "${0%/*}/lua_impls.sh"

build_lua() {
	rm -rf "${lua_impl}" || exit $?
	tar xzf "${lua_archive}" || exit $?
	cd "${lua_impl}" || exit 1
	case "${lua_impl}" in
		lua-* ) make -j "${platform}" || exit $?;;
		LuaJIT-* ) make -j || exit $?;;
		* ) exit 1;;
	esac
	cd .. || exit 1
}

mkdir -p "${lua_base}" || exit $?
cd "${lua_base}" || exit 1

for lua_impl in ${lua_impls}; do
	set_lua_vars
	download "${lua_archive}" "${lua_url}" "${lua_checksum}"
	[ -e "${lua_bin}" ] || build_lua || exit $?
done
