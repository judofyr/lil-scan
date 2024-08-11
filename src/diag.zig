const std = @import("std");

/// Represents parts of the text.
/// This stores the data in terms of line/column in order to be easier to work with.
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

/// The severity of a message.
pub const Severity = enum {
    err,
    warn,
    info,
    hint,
};

/// A message which can be shown to a user.
pub const Message = struct {
    /// The severity of the message.
    severity: Severity = .err,

    /// The text of the message.
    text: []const u8,

    /// A code describing the message.
    code: ?[]const u8 = null,

    /// An URL where the user can learn more about the message.
    url: ?[]const u8 = null,
};
