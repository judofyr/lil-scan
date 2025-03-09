const Scanner = @This();

const std = @import("std");

const parsers = @import("parsers.zig");
const ParseResult = parsers.ParseResult;

const diag = @import("diag.zig");

source: []const u8,
pos: usize = 0,

line_number: usize = 0,
line_start_pos: usize = 0,

failure: ?Failure = null,

pub const Error = error{ParseError};

pub const Failure = struct {
    msg: *const diag.Message,
    span: diag.Span,
};

/// Creates a new scanner which points to the beginning of the given text.
pub fn init(src: []const u8) Scanner {
    return Scanner{ .source = src };
}

pub fn rest(self: *Scanner) []const u8 {
    return self.source[self.pos..];
}

/// Returns true if the scanner is currently at the end.
pub fn isDone(self: *Scanner) bool {
    return self.pos == self.source.len;
}

pub fn skip(self: *Scanner, result: ParseResult) Error!void {
    switch (result) {
        .success => |s| _ = self.advance(s.matched),
        .failure => |f| {
            try self.fail(f.msg, self.restSpan(f.len));
        },
        .nothing => {},
    }
}

pub fn maybe(self: *Scanner, result: ParseResult) Error!?diag.Span {
    switch (result) {
        .success => |s| {
            return self.advance(s.matched);
        },
        .failure => |f| {
            try self.fail(f.msg, self.restSpan(f.len));
        },
        .nothing => return null,
    }
}

pub fn must(self: *Scanner, result: ParseResult, msg: *const diag.Message) Error!diag.Span {
    switch (result) {
        .success => |s| return self.advance(s.matched),
        .failure => |f| {
            try self.fail(f.msg, self.restSpan(f.len));
        },
        .nothing => {
            try self.fail(msg, self.restSpan(1));
        },
    }
}

pub fn advance(self: *Scanner, len: usize) diag.Span {
    const span = self.restSpan(len);
    for (self.source[self.pos..][0..len]) |ch| {
        if (ch == '\n') {
            self.line_number += 1;
            self.line_start_pos = self.pos + 1;
        }
        self.pos += 1;
    }
    return span;
}

pub fn restSpan(self: *Scanner, len: usize) diag.Span {
    return diag.Span{
        .line_number = self.line_number,
        .column_number = self.pos - self.line_start_pos,
        .len = len,
        .line_start_pos = self.line_start_pos,
    };
}

pub fn sliceFromSpan(self: *Scanner, span: diag.Span) []const u8 {
    return self.source[span.line_start_pos + span.column_number ..][0..span.len];
}

pub fn fail(self: *Scanner, msg: *const diag.Message, span: diag.Span) error{ParseError}!noreturn {
    self.failure = Failure{
        .msg = msg,
        .span = span,
    };
    return error.ParseError;
}

const testing = std.testing;

test "simple scanning" {
    var s = Scanner.init("  123 []");

    try testing.expect(!s.isDone());
    try s.skip(parsers.whitespaceAscii(s.rest()));
    try testing.expectEqual(2, s.pos);

    try testing.expect(!s.isDone());
    var num: i64 = undefined;
    _ = try s.must(
        parsers.integerAscii(s.rest(), i64, &num),
        &.{ .text = "Expected integer" },
    );
    try testing.expectEqual(123, num);
    try testing.expectEqual(5, s.pos);

    try testing.expect(!s.isDone());
    try s.skip(parsers.whitespaceAscii(s.rest()));
    try testing.expectEqual(6, s.pos);

    try testing.expect(!s.isDone());
    try testing.expect(try s.maybe(parsers.slice(s.rest(), "[")) != null);
    try testing.expectEqual(7, s.pos);

    try testing.expect(!s.isDone());
    try testing.expect(try s.maybe(parsers.slice(s.rest(), "]")) != null);
    try testing.expectEqual(8, s.pos);

    try testing.expect(s.isDone());
}

test "skip" {
    var s = Scanner.init(" 678");

    // Success:
    try s.skip(parsers.whitespaceAscii(s.rest()));
    try testing.expect(s.failure == null);

    // Nothing:
    try s.skip(parsers.whitespaceAscii(s.rest()));
    try testing.expect(s.failure == null);

    // Failure:
    var num: i8 = undefined;
    const res = s.skip(parsers.integerAscii(s.rest(), i8, &num));
    try testing.expectError(error.ParseError, res);
    try testing.expect(s.failure != null);
}

test "maybe" {
    var s = Scanner.init(" 678");

    // Success:
    try testing.expect(try s.maybe(parsers.whitespaceAscii(s.rest())) != null);
    try testing.expect(s.failure == null);

    // Nothing:
    try testing.expect(try s.maybe(parsers.whitespaceAscii(s.rest())) == null);
    try testing.expect(s.failure == null);

    // Failure:
    var num: i8 = undefined;
    const res = s.maybe(parsers.integerAscii(s.rest(), i8, &num));
    try testing.expectError(error.ParseError, res);
    try testing.expect(s.failure != null);
}

test "must" {
    var s = Scanner.init(" 678");

    // Success:
    _ = try s.must(
        parsers.whitespaceAscii(s.rest()),
        &.{ .text = "Expected whitespace" },
    );

    // Nothing:
    {
        const res = s.must(
            parsers.whitespaceAscii(s.rest()),
            &.{ .text = "Expected whitespace" },
        );
        try testing.expectError(error.ParseError, res);
        try testing.expect(s.failure != null);
        try testing.expectEqualStrings("Expected whitespace", s.failure.?.msg.text);
        s.failure = null;
    }

    // Failure:
    {
        var num: i8 = undefined;
        const res = s.must(
            parsers.integerAscii(s.rest(), i8, &num),
            &.{ .text = "Expected integer" },
        );
        try testing.expectError(error.ParseError, res);
        try testing.expect(s.failure != null);
        try testing.expectEqual(parsers.msgIntegerOverflow, s.failure.?.msg);
        s.failure = null;
    }
}

test "span" {
    var s = Scanner.init("abc\nde");

    _ = try s.must(
        parsers.slice(s.rest(), "abc"),
        &.{ .text = "Expected `abc`" },
    );
    try testing.expectEqual(diag.Span{ // LCOV_EXCL_LINE
        .line_number = 0,
        .column_number = 3,
        .len = 0,
        .line_start_pos = 0,
    }, s.restSpan(0));

    try s.skip(parsers.whitespaceAscii(s.rest()));
    try testing.expectEqual( // LCOV_EXCL_LINE
        diag.Span{
            .line_number = 1,
            .column_number = 0,
            .len = 0,
            .line_start_pos = 4,
        }, s.restSpan(0));

    _ = try s.must(
        parsers.slice(s.rest(), "de"),
        &.{ .text = "Expected `de`" },
    );
    try testing.expectEqual(diag.Span{ // LCOV_EXCL_LINE
        .line_number = 1,
        .column_number = 2,
        .len = 0,
        .line_start_pos = 4,
    }, s.restSpan(0));
}
