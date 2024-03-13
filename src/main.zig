const std = @import("std");
const macho = std.macho;

const dumper = @import("dumper.zig");

const FormatError = dumper.FormatError;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    var args = std.process.args().inner;

    if (args.count < 2) {
        try stdout.print("Usage: ./opack <mach-o file>", .{});
        return;
    }

    _ = args.skip();
    const filepath = args.next().?;
    const file = std.fs.cwd().openFile(filepath, .{}) catch |err| {
        try stderr.print("Error loading file: {!}\n", .{err});
        return;
    };
    defer file.close();

    const reader = file.reader();

    var header64 = macho.mach_header_64{};
    dumper.dump_header(&reader, &header64) catch |err| switch (err) {
        FormatError.NotMachO64 => {
            try stderr.print("Not a machO64 file\n", .{});
            return;
        },
        else => {
            try stderr.print("Dumping header error\n", .{});
            return;
        },
    };
    std.debug.print("magic: {x}\n", .{header64.magic});
}

test "simple test" {}
