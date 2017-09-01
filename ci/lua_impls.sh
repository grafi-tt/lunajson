lua_impls="`cat "${0%/*}/../ci/lua_impls.txt"`"

. ./lua_base.sh

set_lua_vars() {
	lua_archive="${lua_impl}.tar.gz"
	case "$lua_impl" in
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
	lua_lib="${lua_base}/${lua_impl}/lib"
	export LUA_PATH="${0%/*}/../src/?.lua;${0%/*}/../util/?.lua;${lua_lib}/?.lua;"
	export LUA_CPATH="${lua_lib}/?.so;"
}
