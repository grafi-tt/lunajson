#!/bin/sh

for lua in lua lua5.1 lua5.2 lua5.3 luajit; do
	which "$lua" >/dev/null || continue
	[ "$("$lua" -l lunajson -e 'print(require"lunajson".encode({"a", "b", {c="d"}}))')" = '["a","b",{"c":"d"}]' ] \
	&& echo "  ok with $lua" \
	|| echo "! KO with $lua"
done
