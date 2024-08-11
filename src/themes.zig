const diag = @import("diag.zig");

pub const Color = union(enum) {
    neutral,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    gray,

    pub fn escSeq(self: Color) []const u8 {
        return switch (self) {
            .neutral => unreachable, // LCOV_EXCL_LINE
            .red => "\x1b[31m",
            .green => "\x1b[32m",
            .yellow => "\x1b[33m",
            .blue => "\x1b[34m",
            .magenta => "\x1b[35m",
            .cyan => "\x1b[36m",
            .gray => "\x1b[90m",
        };
    }

    pub fn boldEscSeq(self: Color) []const u8 {
        return switch (self) {
            .neutral => "\x1b[1m",
            .red => "\x1b[1;31m",
            .green => "\x1b[1;32m",
            .yellow => "\x1b[1;33m",
            .blue => "\x1b[1;34m",
            .magenta => "\x1b[1;35m",
            .cyan => "\x1b[1;36m",
            .gray => unreachable, // LCOV_EXCL_LINE
        };
    }
};

pub const Formatting = struct {
    bold: bool = false,
    color: Color = .neutral,

    pub fn isDefault(self: Formatting) bool {
        return self.bold == false and self.color == .neutral;
    }

    pub fn withColor(self: Formatting, color: Color) Formatting {
        var f = self;
        f.color = color;
        return f;
    }

    pub fn print(self: Formatting, w: anytype, comptime fmt: []const u8, args: anytype) !void {
        if (self.isDefault()) {
            try w.print(fmt, args);
        } else {
            try w.writeAll(self.escSeq());
            try w.print(fmt, args);
            try w.writeAll(reset);
        }
    }

    pub fn writeAll(self: Formatting, w: anytype, buf: []const u8) !void {
        if (self.isDefault()) {
            try w.writeAll(buf);
        } else {
            try w.writeAll(self.escSeq());
            try w.writeAll(buf);
            try w.writeAll(reset);
        }
    }

    pub fn escSeq(self: Formatting) []const u8 {
        if (self.bold) {
            return self.color.boldEscSeq();
        } else {
            return self.color.escSeq();
        }
    }

    const reset = "\x1b[0m";
};

pub const Theme = struct {
    border: Formatting,
    previewTitle: Formatting,
    previewTarget: Formatting,
    messageSpan: Formatting,

    severityTitle: Formatting,
    severityCode: Formatting,

    errColor: Color,
    warnColor: Color,
    infoColor: Color,
    hintColor: Color,

    pub fn severityColor(self: *const Theme, sev: diag.Severity) Color {
        return switch (sev) {
            .err => self.errColor,
            .warn => self.warnColor,
            .info => self.infoColor,
            .hint => self.hintColor,
        };
    }
};

pub const default_theme: *const Theme = &.{
    .border = .{ .color = .gray },
    .previewTitle = .{ .bold = true, .color = .green },
    .previewTarget = .{ .bold = true },
    .messageSpan = .{ .bold = true },

    .severityTitle = .{ .bold = true },
    .severityCode = .{},

    .errColor = .red,
    .warnColor = .yellow,
    .infoColor = .blue,
    .hintColor = .magenta,
};

pub const noop_theme: *const Theme = &.{
    .border = .{},
    .previewTitle = .{},
    .previewTarget = .{},
    .messageSpan = .{},

    .severityTitle = .{},
    .severityCode = .{},

    .errColor = .neutral,
    .warnColor = .neutral,
    .infoColor = .neutral,
    .hintColor = .neutral,
};
