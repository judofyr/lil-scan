const std = @import("std");
const testing = std.testing;

const diag = @import("diag.zig");

pub const ParseSuccess = struct {
    matched: usize,
};

pub const ParseFailure = struct {
    msg: *const diag.Message,
    len: usize,
};

pub const ParseResult = union(enum) {
    success: ParseSuccess,
    failure: ParseFailure,
    nothing,

    pub fn from_len(len: usize) ParseResult {
        if (len == 0) {
            return .nothing;
        } else {
            return .{ .success = .{ .matched = len } };
        }
    }
};

pub fn eof(text: []const u8) ParseResult {
    if (text.len == 0) {
        return .{ .success = .{ .matched = 0 } };
    } else {
        return .nothing;
    }
}

pub fn slice(text: []const u8, s: []const u8) ParseResult {
    if (std.mem.startsWith(u8, text, s)) {
        return ParseResult.from_len(s.len);
    } else {
        return .nothing;
    }
}

test "slice" {
    try expectSuccess(3, slice("abcdef", "abc"));
    try expectNothing(slice("abcdef", "abdef"));
}

pub fn whenAscii(text: []const u8, f: *const fn (ch: u8) bool) ParseResult {
    var len: usize = 0;
    for (text) |ch| {
        if (!f(ch)) break;
        len += 1;
    }
    return ParseResult.from_len(len);
}

pub fn whitespaceAscii(text: []const u8) ParseResult {
    return whenAscii(text, std.ascii.isWhitespace);
}

pub fn digitAscii(text: []const u8) ParseResult {
    return whenAscii(text, std.ascii.isDigit);
}

pub fn alphabeticAscii(text: []const u8) ParseResult {
    return whenAscii(text, std.ascii.isAlphabetic);
}

pub fn alphanumericAscii(text: []const u8) ParseResult {
    return whenAscii(text, std.ascii.isAlphanumeric);
}

pub fn upperAscii(text: []const u8) ParseResult {
    return whenAscii(text, std.ascii.isUpper);
}

pub fn lowerAscii(text: []const u8) ParseResult {
    return whenAscii(text, std.ascii.isLower);
}

pub fn hexAscii(text: []const u8) ParseResult {
    return whenAscii(text, std.ascii.isHex);
}

test "ascii" {
    try expectSuccess(3, whitespaceAscii(" \t\na\n"));
    try expectSuccess(3, digitAscii("123 3"));
    try expectSuccess(6, alphabeticAscii("abcDEF0"));
    try expectSuccess(8, alphanumericAscii("1abcDEF0!"));
    try expectSuccess(3, upperAscii("DEFabc"));
    try expectSuccess(3, lowerAscii("abcDEF"));
    try expectSuccess(8, hexAscii("abc0123fg"));
}

pub fn notAscii(text: []const u8, f: *const fn (ch: u8) bool) ParseResult {
    if (text.len == 0 or !f(text[0])) {
        return .{ .success = .{ .matched = 0 } };
    } else {
        return .nothing;
    }
}

test "notAscii" {
    {
        const result = notAscii("abc", std.ascii.isAlphabetic);
        try expectNothing(result);
    }

    {
        const result = notAscii(" abc", std.ascii.isAlphabetic);
        try expectSuccess(0, result);
    }

    {
        const result = notAscii("", std.ascii.isAlphabetic);
        try expectSuccess(0, result);
    }
}

pub fn whenUtf8(text: []const u8, f: *const fn (cp: u21) bool) ParseResult {
    var view = std.unicode.Utf8View.initUnchecked(text);
    var it = view.iterator();
    var len: usize = 0;
    while (it.nextCodepoint()) |cp| {
        if (!f(cp)) break;
        len = it.i;
    }
    return ParseResult.from_len(len);
}

test "whenUtf8" {
    const isNorwegianSpecific = struct {
        const ae = std.unicode.utf8Decode("æ") catch unreachable;
        const oo = std.unicode.utf8Decode("ø") catch unreachable;
        const aa = std.unicode.utf8Decode("å") catch unreachable;
        pub fn isNorwegianSpecific(cp: u21) bool {
            return cp == ae or cp == oo or cp == aa;
        }
    }.isNorwegianSpecific;

    try expectSuccess(6, whenUtf8("æøåabc", isNorwegianSpecific));
}

pub const msgIntegerOverflow = &diag.Message{
    .text = "Integer is too large.",
};

fn integerAddDigit(comptime T: type, result: *T, digit: i8) !void {
    result.* = try std.math.mul(T, result.*, 10);
    result.* = try std.math.add(T, result.*, @intCast(digit));
}

pub fn integerAscii(text: []const u8, comptime T: type, result: *T) ParseResult {
    const is_signed = @typeInfo(T).int.signedness == .signed;

    result.* = 0;
    var len: usize = 0;
    var is_neg = false;
    for (text, 0..) |ch, idx| {
        if (is_signed and idx == 0 and ch == '-') {
            is_neg = true;
        } else if (std.ascii.isDigit(ch)) {
            var digit: i8 = @intCast(ch - '0');
            if (is_neg) digit = -digit;
            integerAddDigit(T, result, digit) catch {
                return .{ .failure = ParseFailure{
                    .msg = msgIntegerOverflow,
                    .len = len + 1,
                } };
            };
        } else {
            break;
        }
        len += 1;
    }

    return ParseResult.from_len(len);
}

test "integerAscii" {
    var num: i64 = undefined;
    var unum: u64 = undefined;
    var small_num: i8 = undefined;

    try expectNothing(integerAscii("abc", i64, &num));

    // Exact match
    try expectSuccess(3, integerAscii("123", i64, &num));
    try testing.expectEqual(123, num);

    // Partial match
    try expectSuccess(3, integerAscii("456abc", i64, &num));
    try testing.expectEqual(456, num);

    // At the boundary
    try expectSuccess(3, integerAscii("127", i8, &small_num));
    try testing.expectEqual(127, small_num);

    // Overflow when adding
    try expectFailure(integerAscii("128", i8, &small_num));

    // Overflow when shifting
    try expectFailure(integerAscii("999", i8, &small_num));

    // Negative number
    try expectSuccess(5, integerAscii("-5329", i64, &num));
    try testing.expectEqual(-5329, num);

    // Negative number on unsigned
    try expectNothing(integerAscii("-5329", u64, &unum));
}

fn expectSuccess(matched: usize, res: ParseResult) !void {
    switch (res) {
        .success => |s| {
            try testing.expectEqual(matched, s.matched);
        },
        else => return error.TestExpectedSuccess, // LCOV_EXCL_LINE
    }
}

fn expectNothing(res: ParseResult) !void {
    switch (res) {
        .nothing => {},
        else => return error.TestExpectedNothing, // LCOV_EXCL_LINE
    }
}

fn expectFailure(res: ParseResult) !void {
    switch (res) {
        .failure => {},
        else => return error.TestExpectedNothing, // LCOV_EXCL_LINE
    }
}
