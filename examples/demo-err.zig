const std = @import("std");
const lil = @import("lil-scan");

// Inspired from: https://biomejs.dev/
const ex_biome = lil.PresentationItem{
    .filename = "complexity/useFlatMap.js",
    .text =
    \\const array = ["split", "the text", "into words"];
    \\array.map(sentence => sentence.split(' ')).flat();
    ,
    .msg = &.{
        .severity = .info,
        .text = "The call chain .map().flat() can be replaced with a single .flatMap() call.",
        .code = "lint/complexity/useFlatMap",
    },
    .span = .{
        .line_number = 1,
        .column_number = 0,
        .len = 50,
        .line_start_pos = 51,
    },
};

// https://blog.rust-lang.org/2016/08/10/Shape-of-errors-to-come.html

const ex_rust1 = lil.PresentationItem{
    .filename = "src/test/compile-fail/E0080.rs",
    .text =
    \\  X = (1 << 500)
    ,
    .msg = &.{
        .text = "Attempt to shift left with overflow.",
        .code = "E0080",
        .url = "https://doc.rust-lang.org/error_codes/E0080.html",
    },
    .span = .{
        .line_number = 11,
        .column_number = 2,
        .len = 14,
        .line_start_pos = 0,
    },
};

const ex_rust2 = lil.PresentationItem{
    .filename = "src/test/compile-fail/E0080.rs",
    .text =
    \\  Y = (1 / 0)
    ,
    .msg = &.{
        .text = "Attempt to divide by zero.",
        .code = "E0080",
        .url = "https://doc.rust-lang.org/error_codes/E0080.html",
    },
    .span = .{
        .line_number = 12,
        .column_number = 2,
        .len = 11,
        .line_start_pos = 0,
    },
};

pub fn main() !void {
    var p = lil.Presenter.autoDetect();
    try p.present(ex_biome, lil.DefaultTheme);
    try p.present(ex_rust1, lil.DefaultTheme);
    try p.present(ex_rust2, lil.DefaultTheme);
}
