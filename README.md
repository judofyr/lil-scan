# Lil Scan helps you hand-write parsers in Zig with excellent error messages

Hand-writing parsers isn't actually too bad: You write a function for every syntactical element and by using regular code you get a lot of control of error messages and how to process the parsed structure.
Lil Scan (the younger sibling of Big Parse) is a library which helps you in this process.
It provides a _scanner_ which handles the tokenization step of your parser.
One of the main value it provides is the _diagnostic_ system which makes it easy to provide excellent error messages.

![An example of the error message presented by Lil Scan.](https://judofyr.github.io/lil-scan/images/rust-example1.png)

## Features / non-features

- **Handles scanning/lexing only:**
  - Designed to be used together with a hand-written (recursive descent) parser.
  - No support for traditional context-free parsing algorithms. LL(k), LR, LALR are all terms which Lil Scan knows nothing about.
- **Built-in support for common patterns:**
  - Whitespace, integers, strings.
  - UTF-8/Unicode by default, and anything which works on ASCII is clearly labeled as such.
  - JSON primitives *(planned)*.
- **Flexible diagnostic system:**
  - The scanner returns _spans_ for every token which can be stored for later stages.
- **Excellent presentation of error message:**
  - The source is include with arrows pointing to the exact place.
  - [Deliberate design decisions.](DESIGN.adoc)
  - Automatically detects if stderr is _not_ a TTY and then prints single-line errors.
  - Respects [`NO_COLOR`](https://no-color.org/).
  - Tagging during scanning enables syntax highlighted error messages *(planned)*.
- **Follows best practices:**:
  - Zero allocations.
  - Zero dependencies.
  - 100% test coverage.
  - 100% documentation coverage *(planned)*.
  - 0BSD licensed.

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
_ = try s.must(
   lil.integerAscii(s.rest(), i64, &num),
   &.{.text = "Expected integer"},
);

// (7)
if (try s.maybe(lil.slice(s.rest(), "["))) |_| {
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
