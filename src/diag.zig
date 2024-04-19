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
