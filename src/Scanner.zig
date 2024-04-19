const Scanner = @This();

const std = @import("std");

const parsers = @import("parsers.zig");
const ParseResult = parsers.ParseResult;

const diag = @import("diag.zig");
const Span = diag.Span;

text: []const u8,
pos: usize = 0,

line_number: usize = 0,
line_start_pos: usize = 0,

/// Creates a new scanner which points to the beginning of the given text.
pub fn init(text: []const u8) Scanner {
    return Scanner{ .text = text };
}

pub fn rest(self: *Scanner) []const u8 {
    return self.text[self.pos..];
}

/// Returns true if the scanner is currently at the end.
pub fn isDone(self: *Scanner) bool {
    return self.pos <= self.text.len;
}

pub fn skip(self: *Scanner, result: ParseResult) !void {
    switch (result) {
        .success => |s| self.advance(s.matched),
        .failure => return error.ParseError,
        .nothing => {},
    }
}

pub fn maybe(self: *Scanner, result: ParseResult) !bool {
    switch (result) {
        .success => |s| {
            self.advance(s.matched);
            return true;
        },
        .failure => return error.ParseError,
        .nothing => return false,
    }
}

pub fn must(self: *Scanner, result: ParseResult) !void {
    switch (result) {
        .success => |s| self.advance(s.matched),
        .failure => return error.ParseError,
        .nothing => return error.ParseError,
    }
}

pub fn advance(self: *Scanner, len: usize) void {
    for (self.text[self.pos..][0..len]) |ch| {
        if (ch == '\n') {
            self.line_number += 1;
            self.line_start_pos = self.pos + 1;
        }
        self.pos += 1;
    }
}

pub fn span(self: *Scanner, len: usize) Span {
    return Span{
        .line_number = self.line_number,
        .column_number = self.pos - self.line_start_pos,
        .len = len,
        .line_start_pos = self.line_start_pos,
    };
}

const testing = std.testing;

test "simple scanning" {
    var s = Scanner.init("  123 []");

    try s.skip(parsers.whitespaceAscii(s.rest()));
    try testing.expectEqual(2, s.pos);

    var num: i64 = undefined;
    try s.must(parsers.integerAscii(s.rest(), i64, &num));
    try testing.expectEqual(123, num);
    try testing.expectEqual(5, s.pos);

    try s.skip(parsers.whitespaceAscii(s.rest()));
    try testing.expectEqual(6, s.pos);

    try testing.expect(try s.maybe(parsers.slice(s.rest(), "[")));
    try testing.expectEqual(7, s.pos);

    try testing.expect(try s.maybe(parsers.slice(s.rest(), "]")));
    try testing.expectEqual(8, s.pos);

    try testing.expect(s.isDone());
}

test "skip" {
    var s = Scanner.init(" 678");

    // Success:
    try s.skip(parsers.whitespaceAscii(s.rest()));

    // Nothing:
    try s.skip(parsers.whitespaceAscii(s.rest()));

    // Failure:
    var num: i8 = undefined;
    const res = s.skip(parsers.integerAscii(s.rest(), i8, &num));
    try testing.expectError(error.ParseError, res);
}

test "maybe" {
    var s = Scanner.init(" 678");

    // Success:
    try testing.expect(try s.maybe(parsers.whitespaceAscii(s.rest())));

    // Nothing:
    try testing.expect(!try s.maybe(parsers.whitespaceAscii(s.rest())));

    // Failure:
    var num: i8 = undefined;
    const res = s.maybe(parsers.integerAscii(s.rest(), i8, &num));
    try testing.expectError(error.ParseError, res);
}

test "must" {
    var s = Scanner.init(" 678");

    // Success:
    try s.must(parsers.whitespaceAscii(s.rest()));

    // Nothing:
    {
        const res = s.must(parsers.whitespaceAscii(s.rest()));
        try testing.expectError(error.ParseError, res);
    }

    // Failure:
    {
        var num: i8 = undefined;
        const res = s.must(parsers.integerAscii(s.rest(), i8, &num));
        try testing.expectError(error.ParseError, res);
    }
}

test "span" {
    var s = Scanner.init("abc\nde");

    try s.must(parsers.slice(s.rest(), "abc"));
    try testing.expectEqual(Span{
        .line_number = 0,
        .column_number = 3,
        .len = 0,
        .line_start_pos = 0,
    }, s.span(0));

    try s.skip(parsers.whitespaceAscii(s.rest()));
    try testing.expectEqual(Span{
        .line_number = 1,
        .column_number = 0,
        .len = 0,
        .line_start_pos = 4,
    }, s.span(0));

    try s.must(parsers.slice(s.rest(), "de"));
    try testing.expectEqual(Span{
        .line_number = 1,
        .column_number = 2,
        .len = 0,
        .line_start_pos = 4,
    }, s.span(0));
}
