const std = @import("std");
const macho = std.macho;

const OPacker = @import("opacker.zig").OPacker;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var args = std.process.args().inner;

    if (args.count < 2) {
        try stdout.print("Usage: ./opack <mach-o file>", .{});
        return;
    }

    try OPacker.init(&args);
}

test "simple test" {}
