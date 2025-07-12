const std = @import("std");
const lil = @import("lil-scan");

// Definition of our parser:

const Associativity = enum {
    left,
    right,
    none,
};

const PrecedenceLevel = enum(u8) {
    comparison,
    additive,
    multiplicative,
    negate,
    exponent,
    posate, // opposite of negate?

    fn associativity(self: PrecedenceLevel) Associativity {
        return switch (self) {
            .exponent, .negate => .right,
            .comparison => .none,
            else => .left,
        };
    }
};

const UnaryOperator = enum {
    dash,
    plus,

    fn apply(self: UnaryOperator, expr: i64) i64 {
        return switch (self) {
            .dash => -expr,
            .plus => expr,
        };
    }

    fn level(self: UnaryOperator) PrecedenceLevel {
        return switch (self) {
            .dash => .negate,
            .plus => .posate,
        };
    }

    fn parse(t: []const u8) ?UnaryOperator {
        if (std.mem.eql(u8, t, "-")) {
            return .dash;
        } else if (std.mem.eql(u8, t, "+")) {
            return .plus;
        } else {
            return null;
        }
    }
};

const BinaryOperator = enum {
    plus,
    minus,
    star,
    slash,
    double_star,
    double_eq,

    fn apply(self: BinaryOperator, left: i64, right: i64) i64 {
        return switch (self) {
            .plus => left + right,
            .minus => left - right,
            .star => left * right,
            .slash => @divTrunc(left, right),
            .double_star => std.math.pow(i64, left, right),
            .double_eq => if (left == right) 1 else 0,
        };
    }

    fn level(self: BinaryOperator) PrecedenceLevel {
        return switch (self) {
            .plus, .minus => .additive,
            .star, .slash => .multiplicative,
            .double_star => .exponent,
            .double_eq => .comparison,
        };
    }

    fn parse(t: []const u8) ?BinaryOperator {
        if (std.mem.eql(u8, t, "+")) {
            return .plus;
        } else if (std.mem.eql(u8, t, "-")) {
            return .minus;
        } else if (std.mem.eql(u8, t, "*")) {
            return .star;
        } else if (std.mem.eql(u8, t, "/")) {
            return .slash;
        } else if (std.mem.eql(u8, t, "**")) {
            return .double_star;
        } else if (std.mem.eql(u8, t, "==")) {
            return .double_eq;
        } else {
            return null;
        }
    }
};

fn isOperator(ch: u8) bool {
    switch (ch) {
        '+', '-', '*', '/', '=', '>', '<' => return true,
        else => return false,
    }
}

fn scanTerm(s: *lil.Scanner) !Term {
    if (try s.maybe(lil.whenAscii(s.rest(), isOperator))) |op_span| {
        // Prefix operator.
        const op = UnaryOperator.parse(s.sliceFromSpan(op_span)) orelse {
            try s.fail(&.{ .text = "Unknown prefix operator." }, op_span);
        };
        try s.skip(lil.whitespaceAscii(s.rest()));
        return .{ .part = .{ .prefix = .{ .op = op, .span = op_span } } };
    }

    var num: i64 = undefined;

    if (try s.maybe(lil.slice(s.rest(), "("))) |_| {
        try s.skip(lil.whitespaceAscii(s.rest()));
        num = try scanExpr(s);
        try s.skip(lil.whitespaceAscii(s.rest()));
        _ = try s.must(lil.slice(s.rest(), ")"), &.{ .text = "Expected end of parenthesis." });
    } else {
        _ = try s.must(
            lil.integerAscii(s.rest(), i64, &num),
            &.{ .text = "Expected integer." },
        );
    }

    try s.skip(lil.whitespaceAscii(s.rest()));

    if (try s.maybe(lil.whenAscii(s.rest(), isOperator))) |op_span| {
        // Infix operator.
        const op = BinaryOperator.parse(s.sliceFromSpan(op_span)) orelse {
            try s.fail(&.{ .text = "Unknown infix operator." }, op_span);
        };
        try s.skip(lil.whitespaceAscii(s.rest()));
        return .{ .part = .{ .infix = .{ .expr = num, .op = op, .span = op_span } } };
    }

    return .{ .expr = num };
}

fn parse(s: *lil.Scanner) !i64 {
    try s.skip(lil.whitespaceAscii(s.rest()));
    const result = try scanExpr(s);
    if (!s.isDone()) try s.fail(&.{ .text = "Expected nothing more." }, s.restSpan(1));
    return result;
}

// Main program:

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    var out = std.fs.File.stdout();

    const program_name = args.next() orelse "lil-calc";
    const text = args.next() orelse {
        var buf: [256]u8 = undefined;
        var w = out.writer(&buf);
        try w.interface.print("usage: {s} EXPR\n", .{program_name});
        std.process.exit(0);
    };

    var buf: [4096]u8 = undefined;
    var s = lil.Scanner.init(text);

    const result = parse(&s) catch {
        var p = lil.Presenter.autoDetect(&buf);
        try p.present(lil.SingleMessagePresentation{
            .msg = s.failure.?.msg,
            .span = s.failure.?.span,
            .filename = "(eval)",
            .source = text,
        });
        std.process.exit(1);
    };

    var w = out.writer(&buf);
    try w.interface.print("{s} = {}\n", .{ s.source, result });
}

// Helpers for precedence parsing:

/// Parses a complete expression.
fn scanExpr(s: *lil.Scanner) lil.Scanner.Error!i64 {
    return scanCompleteTerm(s, try scanTerm(s));
}

/// Takes a term (e.g. `1`, `1 +`) and then completes it into an expression.
fn scanCompleteTerm(s: *lil.Scanner, term: Term) lil.Scanner.Error!i64 {
    switch (term) {
        .expr => |expr| return expr,
        .part => |part| return scanCompleteTerm(s, try scanMergeTerm(s, part, try scanTerm(s))),
    }
}

/// Takes a partial term (e.g. `1 +`) and a term (e.g. `2`, `2 *`) and merges it into a single term.
fn scanMergeTerm(s: *lil.Scanner, left: Partial, right: Term) lil.Scanner.Error!Term {
    switch (right) {
        .expr => return left.reduce(right),
        .part => |part| switch (left.associativity(part)) {
            // 1 + 2 + … => 3 + …
            // 1 * 2 + … => 2 + …
            .left => return left.reduce(right),

            // Example: We're `5 + 3 * 8 + 3` and we reach the point where we invoke scanMergeTerm(5 +, 3 *).
            // We then scan another term and recursve on the right-hand side: scanMergeTerm(3 *, 8 +).
            // This is left-associative so it's reduced into `24 +`.
            // Finally we recurse with the initial partial: scanMergeTerm(5 +, 24 +).
            // This is being reduced as well and we return `29 +`.
            .right => return scanMergeTerm(s, left, try scanMergeTerm(s, part, try scanTerm(s))),

            // 1 == 2 == 3 => Fail.
            .none => try s.fail(&.{ .text = "Operator is non-assoative." }, part.span()),
        },
    }
}

/// Given two operators with given precedence levels, returns which of them should be evaluated first.
///
/// Example: The level associativity between `*` and `+` is `.left`.
fn levelAssociativity(left: PrecedenceLevel, right: PrecedenceLevel) Associativity {
    if (left == right) {
        return left.associativity();
    } else if (@intFromEnum(left) > @intFromEnum(right)) {
        return .left;
    } else {
        return .right;
    }
}

/// We deal with two different types of terms in our algorithm:
///
/// - An _expression_ is a plain value, for instance `1`.
/// - A _partial_ is something which can be evaluated. `5 +` is partial infix and `-` is a partial prefix.
const Term = union(enum) {
    expr: i64,
    part: Partial,
};

/// Infix represents a partially parsed infix operator with an evaluated expression on the left-hand side.
const Infix = struct {
    expr: i64,
    op: BinaryOperator,
    span: lil.Span,

    pub fn apply(self: Infix, expr: i64) i64 {
        return self.op.apply(self.expr, expr);
    }
};

/// Prefix represents a partially parsed prefix operator.
pub const Prefix = struct {
    op: UnaryOperator,
    span: lil.Span,

    pub fn apply(self: Prefix, expr: i64) i64 {
        return self.op.apply(expr);
    }
};

const Partial = union(enum) {
    prefix: Prefix,
    infix: Infix,

    /// Reduces the partial into another term, applying the operation stored.
    /// This will not respect any associativity rules.
    ///
    /// Examples:
    /// - `reduce(6 +, 6)` returns `12`.
    /// - `reduce(6 +, 6 *)` returns `12 *`.
    /// - `reduce(6 +, -)` is undefined behavior.
    pub fn reduce(self: Partial, other: Term) Term {
        switch (other) {
            .expr => |expr| return .{ .expr = self.apply(expr) },
            .part => |part| return .{
                .part = .{
                    .infix = .{
                        .expr = self.apply(part.infix.expr),
                        .op = part.infix.op,
                        .span = part.infix.span,
                    },
                },
            },
        }
    }

    pub fn apply(self: Partial, other: i64) i64 {
        switch (self) {
            inline else => |v| return v.apply(other),
        }
    }

    pub fn level(self: Partial) PrecedenceLevel {
        switch (self) {
            inline else => |v| return v.op.level(),
        }
    }

    pub fn span(self: Partial) lil.Span {
        switch (self) {
            inline else => |v| return v.span,
        }
    }

    /// Returns the associativity for two given partials.
    /// This uses `levelAssociativity` internally, but also correctly handles the case where
    /// the right-hand side is a prefix partial (in which case a left associativity is not valid).
    pub fn associativity(self: Partial, other: Partial) Associativity {
        switch (other) {
            .prefix => return .right,
            .infix => return levelAssociativity(self.level(), other.level()),
        }
    }
};
