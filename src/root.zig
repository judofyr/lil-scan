const std = @import("std");

comptime {
    std.testing.refAllDecls(@This());
}

const parsers = @import("parsers.zig");
pub const ParseResult = parsers.ParseResult;
pub const ParseSuccess = parsers.ParseSuccess;
pub const ParseFailure = parsers.ParseFailure;
pub const slice = parsers.slice;
pub const whenAscii = parsers.whenAscii;
pub const whitespaceAscii = parsers.whitespaceAscii;
pub const digitAscii = parsers.digitAscii;
pub const alphabeticAscii = parsers.alphabeticAscii;
pub const alphanumericAscii = parsers.alphanumericAscii;
pub const upperAscii = parsers.upperAscii;
pub const lowerAscii = parsers.lowerAscii;
pub const hexAscii = parsers.hexAscii;
pub const notAscii = parsers.notAscii;
pub const whenUtf8 = parsers.whenUtf8;
pub const integerAscii = parsers.integerAscii;

pub const Scanner = @import("Scanner.zig");

const diag = @import("diag.zig");
pub const Span = diag.Span;
pub const Message = diag.Message;
pub const Severity = diag.Severity;

const presentation = @import("presentation.zig");
pub const PresenterOptions = presentation.PresenterOptions;
pub const Presenter = presentation.Presenter;
pub const SingleMessagePresentation = presentation.SingleMessagePresentation;

const themes = @import("themes.zig");
pub const Color = themes.Color;
pub const Formatting = themes.Formatting;
pub const default_theme = themes.default_theme;
pub const noop_theme = themes.noop_theme;
