const std = @import("std");
const macho = std.macho;

const parser = @import("parser.zig");
const OPacker = @import("opacker.zig").OPacker;
const gpa = @import("gpa.zig");

pub fn main() !void {
    defer _ = gpa.gpa.deinit();
    const stdout = std.io.getStdOut().writer();
    var args = std.process.args().inner;

    if (args.count < 2) {
        try stdout.print("Usage: ./opack <mach-o file>", .{});
        return;
    }

    var opacker = try OPacker.init(&args);

    defer opacker.close();
}

test "simple test" {}
