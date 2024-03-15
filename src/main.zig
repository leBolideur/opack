const std = @import("std");
const macho = std.macho;

const parser = @import("parser.zig");
const OPacker = @import("opacker.zig").OPacker;
const gpa = @import("gpa.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var args = std.process.args().inner;

    if (args.count < 2) {
        try stdout.print("Usage: ./opack <mach-o file>", .{});
        return;
    }

    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer _ = gpa.deinit();
    // const allocator = gpa.allocator();

    // const opacker = OPacker{};
    const opacker = try OPacker.init(&args);
    defer opacker.close();

    // const oFile = parser.MachOFile.load(&args, allocator) catch return;
    // defer allocator.free(oFile);

    // const oData = oFile.parse();
    // defer allocator.free(oData);

    // defer oFile.close();

    // oFile.dump_header() catch return;
    // try oFile.list_load_commands();
    //

    _ = gpa.gpa.deinit();
}

test "simple test" {}
