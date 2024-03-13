const std = @import("std");
const macho = std.macho;

const dumper = @import("dumper.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var args = std.process.args().inner;

    if (args.count < 2) {
        try stdout.print("Usage: ./opack <mach-o file>", .{});
        return;
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const oFile = dumper.MachOFile64.load(&args, allocator) catch return;
    std.debug.print("{s}\n", .{oFile.filepath});
    oFile.dump_header() catch return;
    try oFile.list_load_commands();

    defer oFile.close();
}

test "simple test" {}
