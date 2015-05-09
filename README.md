# Lunajson
Lunajson features SAX-style JSON parser and simple JSON decoder/encoder. It is tested on Lua 5.1, Lua 5.2, Lua 5.3, and LuaJIT.
It is written only in pure Lua and has no dependencies. Even though, since it is carefully optimized, decoding speed even matches to other lpeg-based JSON modules.
The parser and decoder reject inputs not conforms the JSON specification (ECMA-404), and the encoder always yields outputs conforming the specification.
The parser and decoder also handle surrogate pair correctly.

## Install
	luarocks install lunajson

Or you can download source manually and copy `src/*` into somewhere inside `package.path`.

## Simple Usage
	local lunajson = require 'lunajson'
	local jsonstr = '{"Hello"=["lunajson",1.0]}'
	local t = lunajson.decode(jsonstr)
	print(t.Hello[2]) -- prints 1.0
	print(lunajson.encode(t)) -- prints {"Hello"=["lunajson",1.0]}

## API
### lunajson.decode(jsonstr, pos = 1, [nullv, [arraylen]])
Decode `jsonstr` from `pos`. `null` inside JSON will be codes as `nullv` if specified and discarded if not specified.
This function returns the decoded value and `endpos+1`, if `jsonstr` contains valid JSON ending at `endpos`. Otherwise, an error will occur.
If `arraylen` is true, the length of an array `ary` will be stored in `ary[0]`. This behavior is useful when empty arrays should not be confused with empty objects.

### lunajson.encode(value, [nullv])
Encode `value` into a JSON and returns the JSON as a string. If `nullv` is specified, values equal to `nullv` will be encoded as `null`.

This function encode a table `t` as an array if a value `t[1]` is present or a number `t[0]` is present. If `t[0]` is present, its value is considered as the length of the array. Then the array may contain `nil` and those will be encoded as `null`. Otherwise, this function scans non `nil` values starting from index 1. When the table `t` is not an array, it is an object and its all keys must be string.

### lunajson.newparser(input, saxtbl)
### lunajson.newfileparser(filename, saxtbl)
Create a sax parser context which parses `input` or a file specified by `filename`. `input` can be a string to be parsed, or a function that repeatedly returns a chunk of a string to be parsed and `nil` when all inputs are yielded. Following is a sample function of `input` (this sample is essentially same as the implementation of `newfileparser`). Notice that `input` never called once it have returned `nil`.

	local fp = io.open("myfavorite.json")
	local function input()
		local s
		if fp then
			s = fp:read(8192)
			if not s then
				fp:close()
				fp = nil
			end
		end
		return s
	end

`saxtbl` can have following functions. Those function will be called on corresponding events.

- startobject()
- key(s)
- endobject()
- startarray()
- endarray()
- string(s)
- number(n)
- boolean(b)
- null()

A parser context have its position, initially 1.

#### parsercontext.run()
Start parsing from current position.

#### parsercontext.tellpos()
Return current position.

#### parsercontext.tryc()
Return the byte of current position as a number. If input is ended, it returns `nil`. It does not change current position.

#### parsercontext.read(n)
Return the `n`-length string starting from current position, and increase the index by `n`. If the input ends, the returned string and the updated position will be truncated.

## Benchmark
To be appeared.
