#!/bin/sh

cd -- "$(dirname "$0")" || exit 1

# see https://github.com/tst2005/luamodules-all-in-one-file/
# wget https://raw.githubusercontent.com/tst2005/luamodules-all-in-one-file/newtry/pack-them-all.lua
ALLINONE=./aio.lua
[ -f aio.lua ] || ALLINONE=./thirdparty/git/tst2005/lua-aio/aio.lua

ICHECK="";
while [ $# -gt 0 ]; do
	o="$1"; shift
	case "$o" in
		-i) ICHECK=y ;;
	esac
done

W2=true

"$ALLINONE" \
--shebang			src/lunajson.lua \
$(if [ -n "$ICHECK" ]; then
	echo "--icheckinit"
fi) \
--mod lunajson._str_lib			src/lunajson/_str_lib.lua \
--rawmod lunajson._str_lib_lua53	src/lunajson/_str_lib_lua53.lua \
--mod lunajson.sax			src/lunajson/sax.lua \
--mod lunajson.decoder			src/lunajson/decoder.lua \
--mod lunajson.encoder			src/lunajson/encoder.lua \
$(if [ -n "$ICHECK" ]; then
	echo "--icheck"
fi) \
--code 					src/lunajson.lua \
> lunajson.lua

#--mod lunajson.real			src/lunajson.lua
#--luacode				'return require "lunajson.real"'

#"$ALLINONE" --shebang init.lua $( find hate/ -depth -name '*.lua' |while read -r line; do echo "--mod $(echo "$line" | sed 's,\.lua$,,g' | tr / .) ) --code init.lua

