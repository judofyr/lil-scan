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
  - JSON primitives _(planned)_.
- **Flexible diagnostic system:**
  - The scanner returns _spans_ for every token which can be stored for later stages.
- **Excellent presentation of error message:**
  - The source is include with arrows pointing to the exact place.
  - [Deliberate design decisions.](DESIGN.adoc)
  - Automatically detects if stderr is _not_ a TTY and then prints single-line errors.
  - Respects [`NO_COLOR`](https://no-color.org/) and [`CLICOLOR_FORCE`](https://bixense.com/clicolors/).
  - Tagging during scanning enables syntax highlighted error messages _(planned)_.
- **Follows best practices:**:
  - Zero allocations.
  - Zero dependencies.
  - 100% test coverage.
  - 100% documentation coverage.
  - 0BSD licensed.

_Note: There's no promise of active development._
_The planned features are merely what we think would fit within this project._
[_Open an issue_](https://github.com/judofyr/lil-scan/issues/new) _if you need one of the planned features and/or want to help contribute._

## Usage

```zig
const lil = @import("lil-scan");

// Initialize a scanner.
var s = lil.Scanner.init(" 123 ");

// Skip any whitespace.
try s.skip(lil.whitespaceAscii(s.rest()));

// Parse an integer.
var num: i64 = undefined;
_ = try s.must(
   lil.integerAscii(s.rest(), i64, &num),
   &.{.text = "Expected integer"},
);

// Check if there's a `[`:
if (try s.maybe(lil.slice(s.rest(), "["))) |_| {
    // Start parsing an array.
}
```

See also:

- [examples/demo-calc.zig](examples/demo-calc.zig) for a complete example of parsing mathematical expressions.
- The guide below.

## Guide

### 1: Parse functions

A _parse function_ is a standalone function which parses the _prefix_ of some text.
For instance, the `integerAscii` parser when applied to the text `123 + 456` will return that it successfully parsed `123` (and leaves ` + 456` behind).
Lil Scan intentionally decouples the parse functions from the scanning mechanism:
The parse functions are completely stateless functions and you're encouraged to write your own for your specific use case.

More specifically, a parse function is a function which accepts a `[]const u8` and returns a `lil.ParseResult`.
A parse result is one of:

1. `success`: We were able to parse `n` characters.
2. `failure`: We successfully started parsing the text, but then something unexpected appeared in the text.
3. `nothing`: There's no match at the beginning.

Lil Scan currently ships with the following parse functions:

| Name                                                                                                            | Description                                                                      | Example                                   | Failures                                      |
| --------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- | ----------------------------------------- | --------------------------------------------- |
| `eof`                                                                                                           | Returns success on an empty slice.                                               | `lil.slice(text, "")`                     | None.                                         |
| `slice`                                                                                                         | Parses an exact match of a slice.                                                | `lil.slice(text, "if")`                   | None.                                         |
| `whenAscii`                                                                                                     | Parses ASCII text as long as the function returns true.                          | `lil.slice(text, fn(ch: u8) -> bool)`     | None.                                         |
| `whitespaceAscii`, `digitAscii`, `alphabeticAscii`, `alphanumericAscii`, `upperAscii`, `lowerAscii`, `hexAscii` | Parses ASCII text of a certain category. This uses the functions in `std.ascii`. | `lil.whitespaceAscii(text)`               | None.                                         |
| `whenUtf8`                                                                                                      | Parses UTF-8 text as long as the function returns true.                          | `lil.whenUtf8(text, fn(ch: u21) -> bool)` | None.                                         |
| `integerAscii`                                                                                                  | Parses a simple integer (matching the regex `[+-]?\d+`)                          | `lil.integerAscii(text, i64, &dest)`      | When the integer can't fit in the given type. |

### 2: Scanning

The _scanner_ (`lil.Scanner`) keeps track of the current location in the text.
`rest()` returns the remaining text to be parsed and there's a set of _advance functions_ which then advances the scanner.
The general idea is that you pass `rest()` into a parse function and then pass the parse result into the advance function.
All the advance functions will propagate parse failures upwards and they only differ how the deal with `success` vs. `nothing`.

1. `must`: This will cause the scanner to fail if the parse result is `nothing`.
2. `maybe`: This returns `null` if the parse result is `nothing`.
3. `skip`: This doesn't care about `success`. Typically used to skip whitespace and similar.

A scanner might _fail_ at some point.
Any of the advance functions might return `error.ParseError` and if so it will also set the `failure` field on the scanner.
This contains information about the span and the message which caused the error.

### 3: Spans

`must` and `maybe` both return a _span_ which represents a part of the parsed text.
These are lightweight structs, storing indexes, which can be kept around.
Another use case is to use `Scanner.sliceFromSpan` to get the slice of the span and work directly on this during parsing:

```zig
const hex_span = try s.must(lil.hexAscii(s.rest()), &.{.text = "Hex expected."});

// `[]const u8` containing the bytes:
const hex = s.sliceFromSpan(hex_span);
```

### 4: Messages

A _message_ is something which can be shown to a user.
The most common use case is an _error message_ which happens when parsing fails, but Lil Scan's diagnostic system is capable of supporting other types of message as well.

Messages are designed to be _static_:
You define them once as `*const lil.Message` and pass them around as pointers.
There's no way of dynamically creating an error message where you interpolate user values in.
In the future Lil Scan might provide ways of attaching additional metadata to messages.

```zig
pub const Message = struct {
    severity: Severity = .err,
    text: []const u8,
    code: ?[]const u8 = null,
    url: ?[]const u8 = null,
};

pub const Severity = enum {
    err,
    warn,
    info,
    hint,
};
```

### 5: Presentation

A _presenter_ is what presents a message to the user.
It's typically initialized from `autoDetect` which will present errors to `stderr` and automatically detects whether it should use colors and/or show the messages in "expanded mode".

```zig
// Create a presenter:
var pres = lil.Presenter.autoDetect();

// Present a single message:
var s = lil.Scanner.init(source);

parse(s) catch {
   const failure = s.failure.?;
   try pres.present(lil.SingleMessagePresentation{
      .msg = failure.msg,
      .span = failure.span,
      .filename = filename,
      .source = source,
   });
}

```

At the moment the only presentation implemented is `SingleMessagePresentation` which shows a single message.
