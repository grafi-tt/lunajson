orig_lua_impls="`cat "${0%/*}/../ci/lua_impls.txt"`"
lua_impls="`echo "${orig_lua_impls}" | cut -d':' -f1`"

. ./lua_base.sh

set_lua_vars() {
	lua_archive="${lua_impl}.tar.gz"
	case "${lua_impl}" in
		lua-* )
			lua_url="https://www.lua.org/ftp/${lua_archive}"
			lua_bin="${lua_impl}/src/lua"
			;;
		LuaJIT-* )
			lua_url="http://luajit.org/download/${lua_archive}"
			lua_bin="${lua_impl}/src/luajit"
			;;
		* ) exit 1 ;;
	esac
	lua_checksum='x'
	for orig_lua_impl in ${orig_lua_impls}; do
		if [ "${orig_lua_impl%:*}" = "${lua_impl}" ]; then
			lua_checksum="${orig_lua_impl#*:}"
		fi
	done
	[ "${lua_checksum}" = 'x' ] && exit 1
	lua_lib="${lua_base}/${lua_impl}/lib"
	export LUA_PATH="${0%/*}/../src/?.lua;${0%/*}/../util/?.lua;${lua_lib}/?.lua;"
	export LUA_CPATH="${lua_lib}/?.so;"
}

download() {
	archive="$1"
	url="$2"
	checksum="$3"
	if [ ! -e "${archive}" ]; then
		wget "${url}" || exit $?
		if [ ! -e "${archive}" ]; then
			echo "${archive} unavailable" >&2
			exit 1
		fi
	fi
	computed_checksum='x'
	if which sha256sum > /dev/null; then
		computed_checksum="`sha256sum "${archive}" | cut -d' ' -f1`"
	elif which openssl > /dev/null; then
		computed_checksum="`openssl sha256 "${archive}" | cut -d' ' -f2`"
	fi
	if [ "${computed_checksum}" = 'x' ]; then
		echo "sha256sum or openssl command not found!" >&2
		exit 1
	elif [ "${computed_checksum}" != "${checksum}" ]; then
		echo "Checksum validation of ${archive} failed!" >&2
		echo "Expected: ${checksum}" >&2
		echo "Got: ${computed_checksum}" >&2
		exit 1
	fi
}
