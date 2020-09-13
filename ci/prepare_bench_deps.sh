#!/bin/sh

. "${0%/*}/lua_impls.sh"


lpeg_archive="lpeg-1.0.2.tar.gz"
lpeg_url="http://www.inf.puc-rio.br/~roberto/lpeg/${lpeg_archive}"
lpeg_checksum="48d66576051b6c78388faad09b70493093264588fcd0f258ddaab1cdd4a15ffe"

install_lpeg() {
	tar xvf "${lpeg_archive}" -C "${lua_impl}" || exit $?
	cd "${lua_impl}/${lpeg_archive%.tar.gz}" || exit 1
	sed -e "s/^LUADIR.*/LUADIR = ..\\/src/" makefile > makefile.new || exit $?
	mv -f makefile.new makefile || exit $?
	case "${platform}" in
		linux | freebsd )
			make -j linux || exit $?;;
		macosx )
			make -j macosx || exit $?;;
		* ) exit 1;;
	esac
	mv lpeg.so "${lua_lib}" || exit $?
	cd ../.. || exit 1
}


cjson_archive="lua-cjson-2.1.0.tar.gz"
cjson_url="https://www.kyne.com.au/~mark/software/download/${cjson_archive}"
cjson_checksum="51bc69cd55931e0cba2ceae39e9efa2483f4292da3a88a1ed470eda829f6c778"

install_cjson() {
	tar xvf "${cjson_archive}" -C "${lua_impl}" || exit $?
	cd "${lua_impl}/${cjson_archive%.tar.gz}" || exit 1
	sed -e "s/^LUA_INCLUDE_DIR.*/LUA_INCLUDE_DIR = ..\\/src/" Makefile > Makefile.new || exit $?
	mv -f Makefile.new Makefile || exit $?
	if [ "${platform}" = "macosx" ]; then
		sed -e "s/^CJSON_LDFLAGS.*/CJSON_LDFLAGS = -bundle -undefined dynamic_lookup/" Makefile > Makefile.new || exit $?
		mv Makefile.new Makefile || exit $?
	fi
	make -j || exit $?
	mv cjson.so "${lua_lib}" || exit $?
	cd ../.. || exit 1
}


dkjson_archive="dkjson.lua?name=16cbc26080996d9da827df42cb0844a25518eeb3"
dkjson_url="http://dkolf.de/src/dkjson-lua.fsl/raw/dkjson.lua?name=16cbc26080996d9da827df42cb0844a25518eeb3"
dkjson_checksum="1f56a6971ffce3021ece3afdc06163f10bee91264d0d29cc88bbbeb43cffd2d2"

install_dkjson() {
	cp "${dkjson_archive}" "${lua_lib}/dkjson.lua" || exit $?
}


cd "${lua_base}" || exit 1

for dep in lpeg cjson dkjson; do
	eval dep_archive='"$'${dep}_archive'"'
	eval dep_url='"$'${dep}_url'"'
	eval dep_checksum='"$'${dep}_checksum'"'
	if [ -e "${dep_archive}" ]; then
		update=n
	else
		update=y
	fi
	download "${dep_archive}" "${dep_url}" "${dep_checksum}" || exit $?
	for lua_impl in ${lua_impls}; do
		set_lua_vars
		mkdir -p "${lua_lib}" || exit $?
		if [ "${update}" = y -o ! '(' -e "${lua_lib}/${dep}.so" -o -e "${lua_lib}/${dep}.lua" ')' ]; then
			"install_${dep}"
		fi
	done
done
