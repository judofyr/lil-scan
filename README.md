# Lil Scan helps you hand-write parsers in Zig

Lil Scan (the younger sibling of Big Parse) is a library which helps you hand-write parsers in Zig.

## Features / non-features

- Handles scanning/lexing only.
  No support for traditional context-free parsing algorithms. LL(k), LR, LALR are all terms which Lil Scan knows nothing about.
- Easily used inside a hand-written (recursive descent) parser.
- Built-in parsers for common patterns: Whitespace, integers, strings, punctuation.
- Built-in parsers for JSON primitives *(planned)*.
- UTF-8/Unicode by default, and anything which works on ASCII is clearly labeled as such.
- Provides source locations for each token which can be stored for later stages.
- Excellent error messages with arrows pointing to the exact place where it happened *(planned)*.
- Flexible diagnostic system which can annotate both warnings and errors *(planned)*.
- Tagging during scanning enables syntax highlighted error messages *(planned)*.
- Zero dependencies.
- 100% test coverage.

*Note: There's no promise of active development.*
*The planned features are merely what we think would fit within this project.*
[*Open an issue*](https://github.com/judofyr/lil-scan/issues/new) *if you need one of the planned features and/or want to help contribute.*

## Usage

### Scanning

```zig
const lil = @import("lil-scan");

// (1)
var s = lil.Scanner.init(" 123 ");

// (2-4)
try s.skip(lil.whitespaceAscii(s.rest()));

// (5-6)
var num: i64 = undefined;
try s.must(
   lil.integerAscii(s.rest(), i64, &num),
   &.{.text = "Expected integer"},
);

// (7)
if (try s.maybe(lil.slice(s.rest(), "["))) {
    // Start parsing an array.
}
```

1. Intialize a _scanner_ with `Scanner.init`.
2. The scanner is always at a given position.
   `rest()` returns a slice of the remaining text.
3. `whitespaceAscii` is a _parser function_.
   A parser function is a standalone function which takes a slice and attempts to parse at the beginning.
   It returns a _parse result_, which is either `success`, `failure` or `nothing`.
4. `skip` is an _advance function_.
   This takes a parse result and advances the current position of the scanner.
5. Some parse functions also produce additional values.
   These are always provided as pointers which the function writes to.
6. Typically the parse functions returns either `success` or `nothing`.
   If we parse an integer, but `rest()` _starts_ with a non-digit then it returns `nothing`.
   This is needed so we can express "I want to parse an integer, _or_ a string, _or_ a float".
   `must` is an advance function which considers it a parser error if the result is `nothing`.
7. `maybe` is the last advance function: It returns `true` is something matched and `false` if nothing matched.

`skip`, `must` and `maybe` are the only advance functions.
There's a variaty of parser functions (see `src/root.zig`).
