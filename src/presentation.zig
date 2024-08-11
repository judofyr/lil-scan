const std = @import("std");

const diag = @import("diag.zig");
const themes = @import("themes.zig");

// Renders a vertical line which can display titles at certain points.
const TitleLine = struct {
    const Output = []const u8;

    is_first: bool = true,

    pub fn title(self: *TitleLine) Output {
        defer self.is_first = false;

        if (self.is_first) {
            return "╭─⊙ ";
        } else {
            return "├─⊙ ";
        }
    }

    pub fn content(_: *TitleLine) Output {
        return "│ ";
    }

    pub fn close(_: *TitleLine) Output {
        return "╯";
    }
};

const Sidebar = struct {
    const Output = []const u8;

    width: usize,
    buf: [256]u8 = undefined,

    pub fn fmt(self: *Sidebar, comptime format: []const u8, args: anytype) Output {
        return self.fmtWithBorder(" │ ", format, args);
    }

    pub fn fmtLast(self: *Sidebar, comptime format: []const u8, args: anytype) Output {
        return self.fmtWithBorder(" ╵ ", format, args);
    }

    pub fn fmtWithBorder(self: *Sidebar, border: []const u8, comptime format: []const u8, args: anytype) Output {
        var fbs = std.io.fixedBufferStream(self.buf[self.width..(self.buf.len - border.len)]);
        var w = fbs.writer();
        w.print(format, args) catch {};

        const text_width = fbs.getWritten().len;
        for (text_width..self.width) |idx| {
            self.buf[idx] = ' ';
        }

        w.writeAll(border) catch unreachable;
        return self.buf[text_width..][0 .. self.width + border.len];
    }
};

fn severityText(sev: diag.Severity) []const u8 {
    return switch (sev) {
        .err => "Error",
        .warn => "Warning",
        .info => "Info",
        .hint => "Hint",
    };
}

fn writeDiagnosticTitle(w: anytype, theme: *const themes.Theme, msg: *const diag.Message, span: diag.Span, filename: []const u8) !void {
    try theme.severityTitle.withColor(theme.severityColor(msg.severity)).writeAll(w, severityText(msg.severity));
    if (msg.code) |code| {
        try w.writeAll(" ");
        try theme.severityCode.withColor(theme.severityColor(msg.severity)).writeAll(w, code);
    }
    try w.writeAll(" in ");
    try theme.messageSpan.print(w, "{s}:{d}:{d}", .{
        filename,
        span.line_number + 1,
        span.column_number + 1,
    });
}

/// A presentation of a single `Message` happening at the given `Span` in the given `filename`.
/// If `text` is given then it will also show a preview of the line where it happened.
pub const SingleMessagePresentation = struct {
    /// Message to present.
    msg: *const diag.Message,
    /// Filename where the span happened. This would typically be relative to the current directory.
    filename: []const u8,
    /// Where in the file the message happened.
    span: diag.Span,
    /// The source of the file.
    source: ?[]const u8 = null,
    /// A short version of the filename. Used in some places to avoid repeating a long filename.
    short_filename: ?[]const u8 = null,

    /// Writes a simple, single line of the information.
    pub fn writeSimple(self: SingleMessagePresentation, w: anytype, theme: *const themes.Theme) !void {
        try writeDiagnosticTitle(w, theme, self.msg, self.span, self.filename);
        try w.writeAll(": ");
        try w.writeAll(self.msg.text);
        try w.writeAll("\n");
    }

    /// Writes an expanded
    pub fn writeExpanded(self: SingleMessagePresentation, w: anytype, theme: *const themes.Theme) !void {
        const short_filename = self.short_filename orelse std.fs.path.basename(self.filename);

        var tl: TitleLine = .{};

        if (self.source) |text| {
            const from_line_start = text[self.span.line_start_pos..];
            const line_end = std.mem.indexOfScalar(u8, from_line_start, '\n') orelse from_line_start.len;
            const line = from_line_start[0..line_end];
            try theme.border.writeAll(w, tl.title());
            try theme.previewTitle.writeAll(w, "Preview");
            try w.writeAll(" of ");
            try theme.previewTarget.writeAll(w, short_filename);
            try w.writeAll("\n");

            const digits = std.math.log10_int(self.span.line_number + 1) + 1;
            var aligned: Sidebar = .{ .width = digits };

            try theme.border.writeAll(w, tl.content());
            try theme.border.writeAll(w, aligned.fmt("{d}", .{self.span.line_number + 1}));
            try w.writeAll(line);
            try w.writeAll("\n");

            try theme.border.writeAll(w, tl.content());
            try theme.border.writeAll(w, aligned.fmtLast("", .{}));
            try w.writeBytesNTimes(" ", self.span.column_number);
            try w.writeBytesNTimes("^", @min(
                self.span.len,
                // This is our very basic way of handling multiple lines for now:
                // We only show the first line.
                line.len - self.span.column_number,
            ));
            try w.writeAll("\n");
        }

        try theme.border.writeAll(w, tl.title());
        try writeDiagnosticTitle(w, theme, self.msg, self.span, self.filename);
        try w.writeAll("\n");

        try theme.border.writeAll(w, tl.content());
        try w.writeAll(self.msg.text);
        try w.writeAll("\n");

        try theme.border.writeAll(w, tl.content());
        try w.writeAll("\n");

        try theme.border.writeAll(w, tl.content());
        try w.print("File: {s}", .{short_filename});
        try w.writeAll("\n");

        try theme.border.writeAll(w, tl.content());
        try w.print("Line: {d}", .{self.span.line_number + 1});
        try w.writeAll("\n");

        if (self.msg.code) |code| {
            try theme.border.writeAll(w, tl.content());
            try w.print("Code: {s}", .{code});
            try w.writeAll("\n");
        }

        if (self.msg.url) |url| {
            try theme.border.writeAll(w, tl.content());
            try w.print("URL: {s}", .{url});
            try w.writeAll("\n");
        }

        try theme.border.writeAll(w, tl.close());
        try w.writeAll("\n");
    }
};

/// Different options used by the `Presenter`.
pub const PresenterOptions = struct {
    /// When false, no ANSI colors will be printed to the output.
    expand: bool,
    theme: *const themes.Theme,

    /// Detects sensible values for `colors` and `expand` based on the environment and where we
    /// intend to output the message. This will disable colors if `NO_COLOR` environment variable
    /// is set or if the output is not a TTY. Expanded mode will only be available for TTY.
    pub fn autoDetect(file: std.fs.File, color_theme: *const themes.Theme) PresenterOptions {
        const is_tty = file.isTty();
        return PresenterOptions{
            .expand = is_tty,
            .theme = if (hasColors(is_tty)) color_theme else themes.noop_theme,
        };
    }

    // Direct implementation of https://bixense.com/clicolors/
    fn hasColors(is_tty: bool) bool {
        if (std.process.hasEnvVarConstant("NO_COLOR")) {
            return false;
        } else if (std.process.hasEnvVarConstant("CLICOLOR_FORCE")) {
            return true;
        } else {
            return is_tty;
        }
    }
};

pub const Presenter = struct {
    options: PresenterOptions,
    buffered_writer: std.io.BufferedWriter(4096, std.fs.File.Writer),

    pub fn init(file: std.fs.File, options: PresenterOptions) Presenter {
        return Presenter{
            .buffered_writer = .{ .unbuffered_writer = file.writer() },
            .options = options,
        };
    }

    /// Initializes a presenter which outputs to stderr with sensible defaults (see also `PresenterOptions.autoDetect`).
    pub fn autoDetect() Presenter {
        const file = std.io.getStdErr();
        return init(file, PresenterOptions.autoDetect(file, themes.default_theme));
    }

    /// Presents a a single message with the given theme.
    pub fn present(self: *Presenter, item: anytype) !void {
        const w = self.buffered_writer.writer();
        if (self.options.expand) {
            try item.writeExpanded(w, self.options.theme);
        } else {
            try item.writeSimple(w, self.options.theme);
        }
        try self.buffered_writer.flush();
    }
};

const testing = std.testing;
const Scanner = @import("Scanner.zig");
const parsers = @import("parsers.zig");

fn parseHelloWorld(text: []const u8) parsers.ParseResult {
    const token = "hello\nworld";
    if (!std.mem.startsWith(u8, text, "hello\nworld")) return .nothing;
    if (std.ascii.isAlphabetic(text[token.len])) {
        return .{ .failure = .{
            .len = token.len + 1,
            .msg = &.{ .text = "Unexpected token.", .url = "https://example.com/" },
        } };
    }
    return .{ .success = .{ .matched = token.len } };
}

fn parseNumbers(s: *Scanner) !void {
    while (true) {
        try s.skip(parsers.whitespaceAscii(s.rest()));
        if (s.isDone()) break;

        if (try s.maybe(parseHelloWorld(s.rest()))) |_| {
            try s.skip(parsers.whitespaceAscii(s.rest()));
        }

        var num: i8 = undefined;
        _ = try s.must(
            parsers.integerAscii(s.rest(), i8, &num),
            &.{ .text = "Expected integer.", .code = "INT" },
        );
    }
}

const TestCase = struct {
    filename: []const u8,
    source: []const u8,
    expanded: []const u8,
    simple: []const u8,
    adjust_line_start: usize = 0,
};

fn testNumber(case: TestCase) !void {
    var s = Scanner.init(case.source);
    s.line_number += case.adjust_line_start;

    parseNumbers(&s) catch {};
    try testing.expect(s.failure != null);

    const item = SingleMessagePresentation{
        .msg = s.failure.?.msg,
        .span = s.failure.?.span,
        .filename = case.filename,
        .source = case.source,
    };

    {
        var result = std.ArrayList(u8).init(testing.allocator);
        defer result.deinit();

        try item.writeExpanded(result.writer(), themes.noop_theme);
        try testing.expectEqualStrings(case.expanded, result.items);

        result.clearRetainingCapacity();
        try item.writeExpanded(result.writer(), themes.default_theme);
    }

    {
        var result = std.ArrayList(u8).init(testing.allocator);
        defer result.deinit();

        try item.writeSimple(result.writer(), themes.noop_theme);
        try testing.expectEqualStrings(case.simple, result.items);

        result.clearRetainingCapacity();
        try item.writeSimple(result.writer(), themes.default_theme);
    }
}

test "basic" {
    try testNumber(
        .{
            .filename = "src/very/long/hello.txt",
            .source = "12 12 hello",
            .expanded =
            \\╭─⊙ Preview of hello.txt
            \\│ 1 │ 12 12 hello
            \\│   ╵       ^
            \\├─⊙ Error INT in src/very/long/hello.txt:1:7
            \\│ Expected integer.
            \\│ 
            \\│ File: hello.txt
            \\│ Line: 1
            \\│ Code: INT
            \\╯
            \\
            ,
            .simple = "Error INT in src/very/long/hello.txt:1:7: Expected integer.\n",
        },
    );

    try testNumber(
        .{
            .filename = "src/very/long/hello.txt",
            .source = "12 12 hello\nanother line\n",
            .expanded =
            \\╭─⊙ Preview of hello.txt
            \\│ 1 │ 12 12 hello
            \\│   ╵       ^
            \\├─⊙ Error INT in src/very/long/hello.txt:1:7
            \\│ Expected integer.
            \\│ 
            \\│ File: hello.txt
            \\│ Line: 1
            \\│ Code: INT
            \\╯
            \\
            ,
            .simple = "Error INT in src/very/long/hello.txt:1:7: Expected integer.\n",
        },
    );

    try testNumber(
        .{
            .filename = "src/very/long/hello.txt",
            .source = "12 1234 hello",
            .expanded =
            \\╭─⊙ Preview of hello.txt
            \\│ 1 │ 12 1234 hello
            \\│   ╵    ^^^^
            \\├─⊙ Error in src/very/long/hello.txt:1:4
            \\│ Integer is too large.
            \\│ 
            \\│ File: hello.txt
            \\│ Line: 1
            \\╯
            \\
            ,
            .simple = "Error in src/very/long/hello.txt:1:4: Integer is too large.\n",
        },
    );
}

test "big line number" {
    try testNumber(
        .{
            .filename = "src/very/long/hello.txt",
            .source = "12 12 hello",
            .expanded =
            \\╭─⊙ Preview of hello.txt
            \\│ 9 │ 12 12 hello
            \\│   ╵       ^
            \\├─⊙ Error INT in src/very/long/hello.txt:9:7
            \\│ Expected integer.
            \\│ 
            \\│ File: hello.txt
            \\│ Line: 9
            \\│ Code: INT
            \\╯
            \\
            ,
            .simple = "Error INT in src/very/long/hello.txt:9:7: Expected integer.\n",
            .adjust_line_start = 8,
        },
    );

    try testNumber(
        .{
            .filename = "src/very/long/hello.txt",
            .source = "12 12 hello",
            .expanded =
            \\╭─⊙ Preview of hello.txt
            \\│ 10 │ 12 12 hello
            \\│    ╵       ^
            \\├─⊙ Error INT in src/very/long/hello.txt:10:7
            \\│ Expected integer.
            \\│ 
            \\│ File: hello.txt
            \\│ Line: 10
            \\│ Code: INT
            \\╯
            \\
            ,
            .simple = "Error INT in src/very/long/hello.txt:10:7: Expected integer.\n",
            .adjust_line_start = 9,
        },
    );

    try testNumber(
        .{
            .filename = "src/very/long/hello.txt",
            .source = "12 12 hello",
            .expanded =
            \\╭─⊙ Preview of hello.txt
            \\│ 555 │ 12 12 hello
            \\│     ╵       ^
            \\├─⊙ Error INT in src/very/long/hello.txt:555:7
            \\│ Expected integer.
            \\│ 
            \\│ File: hello.txt
            \\│ Line: 555
            \\│ Code: INT
            \\╯
            \\
            ,
            .simple = "Error INT in src/very/long/hello.txt:555:7: Expected integer.\n",
            .adjust_line_start = 554,
        },
    );
}

test "across lines" {
    try testNumber(
        .{
            .filename = "src/very/long/hello.txt",
            .source =
            \\123 123 hello
            \\world 123
            \\123 hello
            \\worldd
            ,
            .expanded =
            \\╭─⊙ Preview of hello.txt
            \\│ 3 │ 123 hello
            \\│   ╵     ^^^^^
            \\├─⊙ Error in src/very/long/hello.txt:3:5
            \\│ Unexpected token.
            \\│ 
            \\│ File: hello.txt
            \\│ Line: 3
            \\│ URL: https://example.com/
            \\╯
            \\
            ,
            .simple = "Error in src/very/long/hello.txt:3:5: Unexpected token.\n",
        },
    );
}
