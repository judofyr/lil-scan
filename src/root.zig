const std = @import("std");

comptime {
    std.testing.refAllDecls(@This());
}

const parsers = @import("parsers.zig");
pub const slice = parsers.slice;
pub const whenAscii = parsers.whenAscii;
pub const whitespaceAscii = parsers.whitespaceAscii;
pub const digitAscii = parsers.digitAscii;
pub const alphabeticAscii = parsers.alphabeticAscii;
pub const alphanumericAscii = parsers.alphanumericAscii;
pub const upperAscii = parsers.upperAscii;
pub const lowerAscii = parsers.lowerAscii;
pub const hexAscii = parsers.hexAscii;
pub const andNotAscii = parsers.andNotAscii;
pub const whenUtf8 = parsers.whenUtf8;
pub const integerAscii = parsers.integerAscii;

pub const Scanner = @import("Scanner.zig");

const diag = @import("diag.zig");
pub const Span = diag.Span;
pub const Diagnostic = diag.Diagnostic;
pub const Severity = diag.Severity;

const presentation = @import("presentation.zig");
pub const PresenterOptions = presentation.PresenterOptions;
pub const Presenter = presentation.Presenter;
pub const PresentationItem = presentation.PresentationItem;

const themes = @import("themes.zig");
pub const Color = themes.Color;
pub const Formatting = themes.Formatting;
pub const DefaultTheme = themes.DefaultTheme;
pub const NoopTheme = themes.NoopTheme;
