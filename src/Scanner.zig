const Scanner = @This();

const std = @import("std");

const parsers = @import("parsers.zig");
const ParseResult = parsers.ParseResult;

const diag = @import("diag.zig");

text: []const u8,
pos: usize = 0,

line_number: usize = 0,
line_start_pos: usize = 0,

diag_handler: ?diag.Handler = null,

/// Creates a new scanner which points to the beginning of the given text.
pub fn init(text: []const u8) Scanner {
    return Scanner{ .text = text };
}

pub fn rest(self: *Scanner) []const u8 {
    return self.text[self.pos..];
}

/// Returns true if the scanner is currently at the end.
pub fn isDone(self: *Scanner) bool {
    return self.pos == self.text.len;
}

pub fn skip(self: *Scanner, result: ParseResult) !void {
    switch (result) {
        .success => |s| self.advance(s.matched),
        .failure => |f| {
            self.reportSpan(f.msg, self.restSpan(f.len));
            return error.ParseError;
        },
        .nothing => {},
    }
}

pub fn maybe(self: *Scanner, result: ParseResult) !bool {
    switch (result) {
        .success => |s| {
            self.advance(s.matched);
            return true;
        },
        .failure => |f| {
            self.reportSpan(f.msg, self.restSpan(f.len));
            return error.ParseError;
        },
        .nothing => return false,
    }
}

pub fn must(self: *Scanner, result: ParseResult, msg: *const diag.Message) !void {
    switch (result) {
        .success => |s| self.advance(s.matched),
        .failure => |f| {
            self.reportSpan(f.msg, self.restSpan(f.len));
            return error.ParseError;
        },
        .nothing => {
            self.reportSpan(msg, self.restSpan(1));
            return error.ParseError;
        },
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

pub fn restSpan(self: *Scanner, len: usize) diag.Span {
    return diag.Span{
        .line_number = self.line_number,
        .column_number = self.pos - self.line_start_pos,
        .len = len,
        .line_start_pos = self.line_start_pos,
    };
}

pub fn reportSpan(self: *Scanner, msg: *const diag.Message, span: diag.Span) void {
    self.reportDiag(diag.Diagnostic{
        .msg = msg,
        .span = span,
    });
}

pub fn reportDiag(self: *Scanner, diagnostic: diag.Diagnostic) void {
    if (self.diag_handler) |handler| {
        handler.handle(diagnostic);
    }
}

const testing = std.testing;

test "simple scanning" {
    var s = Scanner.init("  123 []");

    try testing.expect(!s.isDone());
    try s.skip(parsers.whitespaceAscii(s.rest()));
    try testing.expectEqual(2, s.pos);

    try testing.expect(!s.isDone());
    var num: i64 = undefined;
    try s.must(parsers.integerAscii(s.rest(), i64, &num), &.{ .text = "Expected integer" });
    try testing.expectEqual(123, num);
    try testing.expectEqual(5, s.pos);

    try testing.expect(!s.isDone());
    try s.skip(parsers.whitespaceAscii(s.rest()));
    try testing.expectEqual(6, s.pos);

    try testing.expect(!s.isDone());
    try testing.expect(try s.maybe(parsers.slice(s.rest(), "[")));
    try testing.expectEqual(7, s.pos);

    try testing.expect(!s.isDone());
    try testing.expect(try s.maybe(parsers.slice(s.rest(), "]")));
    try testing.expectEqual(8, s.pos);

    try testing.expect(s.isDone());
}

test "skip" {
    var s = Scanner.init(" 678");
    var d: ?diag.Diagnostic = null;
    s.diag_handler = diag.pointerHandler(&d);

    // Success:
    try s.skip(parsers.whitespaceAscii(s.rest()));
    try testing.expect(d == null);

    // Nothing:
    try s.skip(parsers.whitespaceAscii(s.rest()));
    try testing.expect(d == null);

    // Failure:
    var num: i8 = undefined;
    const res = s.skip(parsers.integerAscii(s.rest(), i8, &num));
    try testing.expectError(error.ParseError, res);
    try testing.expect(d != null);
}

test "maybe" {
    var s = Scanner.init(" 678");
    var d: ?diag.Diagnostic = null;
    s.diag_handler = diag.pointerHandler(&d);

    // Success:
    try testing.expect(try s.maybe(parsers.whitespaceAscii(s.rest())));
    try testing.expect(d == null);

    // Nothing:
    try testing.expect(!try s.maybe(parsers.whitespaceAscii(s.rest())));
    try testing.expect(d == null);

    // Failure:
    var num: i8 = undefined;
    const res = s.maybe(parsers.integerAscii(s.rest(), i8, &num));
    try testing.expectError(error.ParseError, res);
    try testing.expect(d != null);
}

test "must" {
    var s = Scanner.init(" 678");
    var d: ?diag.Diagnostic = null;
    s.diag_handler = diag.pointerHandler(&d);

    // Success:
    try s.must(
        parsers.whitespaceAscii(s.rest()),
        &.{ .text = "Expected whitespace" },
    );
    try testing.expect(d == null);

    // Nothing:
    {
        const res = s.must(
            parsers.whitespaceAscii(s.rest()),
            &.{ .text = "Expected whitespace" },
        );
        try testing.expectError(error.ParseError, res);
        try testing.expect(d != null);
        try testing.expectEqualStrings("Expected whitespace", d.?.msg.text);
        d = null;
    }

    // Failure:
    {
        var num: i8 = undefined;
        const res = s.must(
            parsers.integerAscii(s.rest(), i8, &num),
            &.{ .text = "Expected integer" },
        );
        try testing.expectError(error.ParseError, res);
        try testing.expect(d != null);
        try testing.expectEqual(parsers.msgIntegerOverflow, d.?.msg);
        d = null;
    }
}

test "span" {
    var s = Scanner.init("abc\nde");

    try s.must(
        parsers.slice(s.rest(), "abc"),
        &.{ .text = "Expected `abc`" },
    );
    try testing.expectEqual(diag.Span{
        .line_number = 0,
        .column_number = 3,
        .len = 0,
        .line_start_pos = 0,
    }, s.restSpan(0));

    try s.skip(parsers.whitespaceAscii(s.rest()));
    try testing.expectEqual(diag.Span{
        .line_number = 1,
        .column_number = 0,
        .len = 0,
        .line_start_pos = 4,
    }, s.restSpan(0));

    try s.must(
        parsers.slice(s.rest(), "de"),
        &.{ .text = "Expected `de`" },
    );
    try testing.expectEqual(diag.Span{
        .line_number = 1,
        .column_number = 2,
        .len = 0,
        .line_start_pos = 4,
    }, s.restSpan(0));
}

test "diag handler" {
    var s = Scanner.init("abc");

    var list = std.ArrayList(diag.Diagnostic).init(testing.allocator);
    defer list.deinit();
    s.diag_handler = diag.arrayListHandler(&list);
    s.reportSpan(&.{ .text = "Integer expected" }, s.restSpan(0));

    try testing.expectEqual(1, list.items.len);
}
