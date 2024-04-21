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

const ExpandedPresentationItem = struct {
    filename: []const u8,
    short_filename: []const u8,
    line: []const u8,
    diagnostic: *const diag.Diagnostic,

    pub fn writeTo(self: ExpandedPresentationItem, w: anytype, theme: type) !void {
        var tl: TitleLine = .{};

        try theme.border().writeAll(w, tl.title());
        try theme.previewTitle().writeAll(w, "Preview");
        try w.writeAll(" of ");
        try theme.previewTarget().writeAll(w, self.short_filename);
        try w.writeAll("\n");

        const digits = std.math.log10_int(self.diagnostic.span.line_number + 1) + 1;
        var aligned: Sidebar = .{ .width = digits };

        try theme.border().writeAll(w, tl.content());
        try theme.border().writeAll(w, aligned.fmt("{d}", .{self.diagnostic.span.line_number + 1}));
        try w.writeAll(self.line);
        try w.writeAll("\n");

        try theme.border().writeAll(w, tl.content());
        try theme.border().writeAll(w, aligned.fmtLast("", .{}));
        try w.writeBytesNTimes(" ", self.diagnostic.span.column_number);
        try w.writeBytesNTimes("^", @min(
            self.diagnostic.span.len,
            // This is our very basic way of handling multiple lines for now:
            // We only show the first line.
            self.line.len - self.diagnostic.span.column_number,
        ));
        try w.writeAll("\n");

        try theme.border().writeAll(w, tl.title());
        try writeDiagnosticTitle(w, theme, self.diagnostic, self.filename);
        try w.writeAll("\n");

        try theme.border().writeAll(w, tl.content());
        try w.writeAll(self.diagnostic.msg.text);
        try w.writeAll("\n");

        try theme.border().writeAll(w, tl.content());
        try w.writeAll("\n");

        try theme.border().writeAll(w, tl.content());
        try w.print("File: {s}", .{self.short_filename});
        try w.writeAll("\n");

        try theme.border().writeAll(w, tl.content());
        try w.print("Line: {d}", .{self.diagnostic.span.line_number + 1});
        try w.writeAll("\n");

        if (self.diagnostic.msg.code) |code| {
            try theme.border().writeAll(w, tl.content());
            try w.print("Code: {s}", .{code});
            try w.writeAll("\n");
        }

        try theme.border().writeAll(w, tl.close());
        try w.writeAll("\n");
    }
};

fn writeDiagnosticTitle(w: anytype, theme: type, diagnostic: *const diag.Diagnostic, filename: []const u8) !void {
    try theme.severityTitle(diagnostic.msg.severity).writeAll(w, severityText(diagnostic.msg.severity));
    if (diagnostic.msg.code) |code| {
        try w.writeAll(" ");
        try theme.severityCode(diagnostic.msg.severity).writeAll(w, code);
    }
    try w.writeAll(" in ");
    try theme.messageSpan().print(w, "{s}:{d}:{d}", .{
        filename,
        diagnostic.span.line_number + 1,
        diagnostic.span.column_number + 1,
    });
}

pub const PresentationItem = struct {
    diagnostic: *const diag.Diagnostic,
    filename: []const u8,
    text: []const u8,

    pub fn expand(self: PresentationItem) ExpandedPresentationItem {
        const from_line_start = self.text[self.diagnostic.span.line_start_pos..];
        const line_end = std.mem.indexOfScalar(u8, from_line_start, '\n') orelse from_line_start.len;
        const line = from_line_start[0..line_end];

        return ExpandedPresentationItem{
            .filename = self.filename,
            .short_filename = std.fs.path.basename(self.filename),
            .line = line,
            .diagnostic = self.diagnostic,
        };
    }

    pub fn writeTo(self: PresentationItem, w: anytype, theme: type) !void {
        try writeDiagnosticTitle(w, theme, self.diagnostic, self.filename);
        try w.writeAll(": ");
        try w.writeAll(self.diagnostic.msg.text);
        try w.writeAll("\n");
    }
};

pub const PresenterOptions = struct {
    colors: bool,
    expand: bool,

    pub fn autoDetect(file: std.fs.File) PresenterOptions {
        var buf: [0]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);
        const is_tty = file.isTty();
        return PresenterOptions{
            .colors = is_tty and !(std.process.hasEnvVar(fba.allocator(), "NO_COLOR") catch true),
            .expand = is_tty,
        };
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

    pub fn autoDetect() Presenter {
        const file = std.io.getStdErr();
        return init(file, PresenterOptions.autoDetect(file));
    }

    pub fn present(self: *Presenter, item: PresentationItem, theme: type) !void {
        const w = self.buffered_writer.writer();
        if (self.options.expand) {
            if (self.options.colors) {
                try item.expand().writeTo(w, theme);
            } else {
                try item.expand().writeTo(w, themes.NoopTheme);
            }
        } else {
            if (self.options.colors) {
                try item.writeTo(w, theme);
            } else {
                try item.writeTo(w, themes.NoopTheme);
            }
        }
        try self.buffered_writer.flush();
    }
};

const testing = std.testing;
const Scanner = @import("Scanner.zig");
const parsers = @import("parsers.zig");

fn parseNumbers(s: *Scanner) !void {
    while (true) {
        try s.skip(parsers.whitespaceAscii(s.rest()));
        if (s.isDone()) break;

        try s.skip(parsers.andNotAscii(
            parsers.slice(s.rest(), "hello\nworld"),
            std.ascii.isWhitespace,
            &.{ .text = "Unexpected whitespace." },
        ));

        var num: i8 = undefined;
        try s.must(
            parsers.integerAscii(s.rest(), i8, &num),
            &.{ .text = "Expected integer.", .code = "INT" },
        );
    }
}

const TestCase = struct {
    filename: []const u8,
    text: []const u8,
    expanded: []const u8,
    simple: []const u8,
    adjust_line_start: usize = 0,
};

fn testNumber(case: TestCase) !void {
    var s = Scanner.init(case.text);
    s.line_number += case.adjust_line_start;

    var d: ?diag.Diagnostic = null;
    s.diag_handler = diag.pointerHandler(&d);
    parseNumbers(&s) catch {};
    try testing.expect(d != null);

    const item = PresentationItem{
        .diagnostic = &d.?,
        .filename = case.filename,
        .text = case.text,
    };

    {
        var result = std.ArrayList(u8).init(testing.allocator);
        defer result.deinit();

        try item.writeTo(result.writer(), themes.NoopTheme);
        try testing.expectEqualStrings(case.simple, result.items);

        result.clearRetainingCapacity();
        try item.writeTo(result.writer(), themes.DefaultTheme);
    }

    {
        var result = std.ArrayList(u8).init(testing.allocator);
        defer result.deinit();

        try item.expand().writeTo(result.writer(), themes.NoopTheme);
        try testing.expectEqualStrings(case.expanded, result.items);

        result.clearRetainingCapacity();
        try item.expand().writeTo(result.writer(), themes.DefaultTheme);
    }
}

test "basic" {
    try testNumber(
        .{
            .filename = "src/very/long/hello.txt",
            .text = "12 12 hello",
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
            .text = "12 12 hello\nanother line\n",
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
            .text = "12 1234 hello",
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
            .text = "12 12 hello",
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
            .text = "12 12 hello",
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
            .text = "12 12 hello",
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
            .text =
            \\123 123 hello
            \\world123
            \\123 hello
            \\world 123
            ,
            .expanded =
            \\╭─⊙ Preview of hello.txt
            \\│ 3 │ 123 hello
            \\│   ╵     ^^^^^
            \\├─⊙ Error in src/very/long/hello.txt:3:5
            \\│ Unexpected whitespace.
            \\│ 
            \\│ File: hello.txt
            \\│ Line: 3
            \\╯
            \\
            ,
            .simple = "Error in src/very/long/hello.txt:3:5: Unexpected whitespace.\n",
        },
    );
}