const std = @import("std");
const macho = std.macho;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var args = std.process.args().inner;

    if (args.count < 2) {
        try stdout.print("Usage: ./opack <mach-o file>", .{});
        std.process.exit(0);
    }

    _ = args.skip();
    const filepath = args.next().?;
    const file = try std.fs.cwd().openFile(filepath, .{});
    defer file.close();

    const reader = file.reader();

    const header = try reader.readStruct(macho.mach_header_64);
    std.debug.print("magic: {x}\n", .{header.magic});
}

test "simple test" {}
