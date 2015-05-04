local decode = require 'lunajson.decode'
local encode = require 'lunajson.encode'
local sax = require 'lunajson.sax'
return {
	decode = decode,
	encode = encode,
	newparser = sax.newparser,
	newfileparser = sax.newfileparser,
}
