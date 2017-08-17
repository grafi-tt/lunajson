lua_dists="lua-5.1.5 lua-5.2.4 lua-5.3.4 LuaJIT-2.0.5"

. ./lua_base.sh

set_lua_vars() {
	lua_archive="${lua_dist}.tar.gz"
	case "$lua_dist" in
		lua-* )
			lua_url="https://www.lua.org/ftp/${lua_archive}"
			lua_bin="${lua_dist}/src/lua"
			;;
		LuaJIT-* )
			lua_url="http://luajit.org/download/${lua_archive}"
			lua_bin="${lua_dist}/src/luajit"
			;;
		* ) exit 1 ;;
	esac
	lua_lib="${lua_base}/${lua_dist}/lib"
	export LUA_PATH="${0%/*}/../src/?.lua;${0%/*}/../util/?.lua;${lua_lib}/?.lua;"
	export LUA_CPATH="${lua_lib}/?.so;"
}
