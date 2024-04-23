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

    var out = std.io.getStdOut();

    const program_name = args.next() orelse "lil-calc";
    const text = args.next() orelse {
        try out.writer().print("usage: {s} EXPR\n", .{program_name});
        std.process.exit(0);
    };

    var p = lil.Presenter.autoDetect();
    var s = lil.Scanner.init(text);

    const result = parse(&s) catch {
        try p.present(lil.PresentationItem{
            .msg = s.failure.?.msg,
            .span = s.failure.?.span,
            .filename = "(eval)",
            .text = text,
        }, lil.DefaultTheme);
        std.process.exit(1);
    };

    try out.writer().print("{s} = {}\n", .{ s.text, result });
}

// Helpers for precedence parsing:

fn levelAssociativity(left: PrecedenceLevel, right: PrecedenceLevel) Associativity {
    if (left == right) {
        return left.associativity();
    } else if (@intFromEnum(left) > @intFromEnum(right)) {
        return .left;
    } else {
        return .right;
    }
}

const Infix = struct {
    expr: i64,
    op: BinaryOperator,
    span: lil.Span,

    pub fn apply(self: Infix, expr: i64) i64 {
        return self.op.apply(self.expr, expr);
    }
};

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

    pub fn merge(self: Partial, other: Term) Term {
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

    pub fn associativity(self: Partial, other: Partial) Associativity {
        switch (other) {
            .prefix => return .right,
            .infix => return levelAssociativity(self.level(), other.level()),
        }
    }
};

const Term = union(enum) {
    expr: i64,
    part: Partial,
};

fn scanExpr(s: *lil.Scanner) lil.Scanner.Error!i64 {
    return scanTermIntoExpr(s, try scanTerm(s));
}

fn scanTermIntoExpr(s: *lil.Scanner, node: Term) lil.Scanner.Error!i64 {
    switch (node) {
        .expr => |expr| return expr,
        .part => |part| return scanTermIntoExpr(s, try scanExprAfterTerm(s, part, try scanTerm(s))),
    }
}

fn scanExprAfterTerm(s: *lil.Scanner, left: Partial, right: Term) lil.Scanner.Error!Term {
    switch (right) {
        .expr => return left.merge(right),
        .part => |part| switch (left.associativity(part)) {
            // 1 + 2 + … => 3 + …
            // 1 * 2 + … => 2 + …
            .left => return left.merge(right),
            // 1 + 2 * … => (1 +).merge(2 * …)
            .right => return scanExprAfterTerm(s, left, try scanExprAfterTerm(s, part, try scanTerm(s))),
            // 1 == 2 == 3 => Fail.
            .none => try s.fail(&.{ .text = "Operator is non-assoative." }, part.span()),
        },
    }
}
