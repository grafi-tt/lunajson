#!/bin/sh

. "${0%/*}/lua_impls.sh"


lpeg_archive="lpeg-1.0.1.tar.gz"
lpeg_url="http://www.inf.puc-rio.br/~roberto/lpeg/${lpeg_archive}"

install_lpeg() {
	tar xvf "$lpeg_archive" -C "$lua_impl" || exit $?
	cd "${lua_impl}/${lpeg_archive%.tar.gz}"
	sed -e "s/^LUADIR.*/LUADIR = ..\\/src/" makefile > makefile.new
	mv -f makefile.new makefile
	case "$platform" in
		linux | freebsd )
			make linux || exit $?;;
		macosx )
			make macosx || exit $?;;
		* ) exit 1;;
	esac
	mv lpeg.so "$lua_lib" || exit $?
	cd ../..
}


cjson_archive="lua-cjson-2.1.0.tar.gz"
cjson_url="https://www.kyne.com.au/~mark/software/download/${cjson_archive}"

install_cjson() {
	tar xvf "$cjson_archive" -C "$lua_impl" || exit $?
	cd "${lua_impl}/${cjson_archive%.tar.gz}"
	sed -e "s/^LUA_INCLUDE_DIR.*/LUA_INCLUDE_DIR = ..\\/src/" Makefile > Makefile.new
	mv -f Makefile.new Makefile
	if [ "$platform" = "macosx" ]; then
		sed -e "s/^CJSON_LDFLAGS.*/CJSON_LDFLAGS = -bundle -undefined dynamic_lookup/" Makefile > Makefile.new
		mv Makefile.new Makefile
	fi
	make || exit $?
	mv cjson.so "$lua_lib" || exit $?
	cd ../..
}


dkjson_archive="dkjson.lua?name=16cbc26080996d9da827df42cb0844a25518eeb3"
dkjson_url="http://dkolf.de/src/dkjson-lua.fsl/raw/dkjson.lua?name=16cbc26080996d9da827df42cb0844a25518eeb3"

install_dkjson() {
	cp "$dkjson_archive" "${lua_lib}/dkjson.lua"
}


cd "${lua_base}" || exit 1

for dep in lpeg cjson dkjson; do
	update=n
	eval dep_archive='"$'${dep}_archive'"'
	eval dep_url='"$'${dep}_url'"'
	if [ ! -e "$dep_archive" ]; then
		wget "$dep_url"
		update=y
	fi
	for lua_impl in $lua_impls; do
		set_lua_vars
		mkdir -p "$lua_lib"
		if [ "$update" = y -o ! '(' -e "${lua_lib}/${dep}.so" -o -e "${lua_lib}/${dep}.lua" ')' ]; then
			"install_${dep}"
		fi
	done
done
