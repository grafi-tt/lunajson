# 1.2.4

## Bugs found and fixed by Claude Opus 5.5

* Fix decoding of surrogate pairs: a high surrogate followed by a non-surrogate `\u` escape is rejected, and an error no longer affects the next call of a reused decoder
* Fix decoding of numbers in locales whose decimal mark is not `.` (changing the locale after loading lunajson is not supported)
* Decode `-0` as `-0.0` in the SAX parser, and do not decode `0` as `-0` on Lua 5.1
* Decode big integers as floats on Lua 5.3.0-5.3.2, which wrapped them around (e.g. `18446744073709551617` became `1`)
* Encode integers on Lua 5.3+ without losing precision beyond 2^53
* Do not output invalid JSON for an array whose length `[0]` is between 0 and 1
* Bound the key cache of the decoder, which grew without limit when the decoder was reused
* The decoder and the encoder no longer keep the last input or output alive after each call
* Fix several bugs of the SAX parser: quadratic time for strings spanning multiple chunks, wrong bytes from `read()` with chunks of varying lengths (affecting `newfileparser`), rejection of `[` or `{` directly after a number at a chunk boundary, and a wrong `tellpos()` after the end of a string source
* Add regression tests for the bugs above and tests for syntax errors and encoder errors, and fix the parser test, which skipped its second round

## Other changes

* Document error handling of `encode()` (Thanks to @ypnos)
* Fix a typo in README (Thanks to @tst2005)
* Migrate CI to GitHub Actions, including Windows

# 1.2.3

* Fix SAX decoding of empty array/object (Thanks to @treahard and @Benjamin-Dobell)

# 1.2.2

* Accept multiple spaces after colon (this bug introduced in 1.2.1)
* Slight decoding speed up

# 1.2.1

* Performance improvement of decoding (Thanks to @muhmuhten)
* Store io.open before setting _ENV=nil in sax (Thanks to @muhmuhten)
* Fixes and sha256 validation in CI / benchmark scripts

# 1.2.0

* For ease of embedded use, the decoder and the SAX parser are made self-contained one file implementation.
* `1` is decoded as an integer on Lua 5.3.
* Number parsing routine is changed. Now `-?[0-9][-+.A-Za-z0-9]*` is detected as a number, and its conformance to JSON spec is checked.
* Automated testing.
* Cool logo :)
* Bug fixes.
