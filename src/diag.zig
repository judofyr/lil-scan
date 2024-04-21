const std = @import("std");

pub const Span = struct {
    /// The line number (0-indexed) where the span starts.
    line_number: usize,
    /// The column (0-indexed) on this line where the span starts.
    column_number: usize,
    /// The length of the span. This may cross newlines.
    len: usize,

    /// The byte position where this line starts.
    line_start_pos: usize,
};

pub const Severity = enum {
    err,
    warn,
    info,
    hint,
};

pub const Message = struct {
    severity: Severity = .err,
    text: []const u8,
    code: ?[]const u8 = null,
};

pub const Diagnostic = struct {
    span: Span,
    msg: *const Message,
};

pub const Handler = struct {
    ctx: ?*anyopaque,
    callback: *const fn (ctx: ?*anyopaque, diagnostic: Diagnostic) void,

    pub fn handle(self: Handler, diagnostic: Diagnostic) void {
        self.callback(self.ctx, diagnostic);
    }
};

pub fn arrayListHandler(list: *std.ArrayList(Diagnostic)) Handler {
    const callback = struct {
        fn callback(ctx: ?*anyopaque, diagnostic: Diagnostic) void {
            var l: *std.ArrayList(Diagnostic) = @ptrCast(@alignCast(ctx));
            l.append(diagnostic) catch {};
        }
    }.callback;

    return Handler{ .ctx = list, .callback = callback };
}

pub fn pointerHandler(ptr: *?Diagnostic) Handler {
    const callback = struct {
        fn callback(ctx: ?*anyopaque, diagnostic: Diagnostic) void {
            const p: *?Diagnostic = @ptrCast(@alignCast(ctx));
            p.* = diagnostic;
        }
    }.callback;

    return Handler{ .ctx = ptr, .callback = callback };
}
