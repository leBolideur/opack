const std = @import("std");
const macho = std.macho;

const MachOFile = @import("parser.zig").MachOFile;
const OData = @import("odata.zig").OData;
const printer = @import("printer.zig");

const omap_import = @import("omap.zig");
const OMap = omap_import.OMap;
const MapRequest = omap_import.MapRequest;

const GPAConfig = .{ .verbose_log = false };

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var args = std.process.args().inner;

    if (args.count < 2) {
        try stdout.print("Usage: ./opack <mach-o file>", .{});
        return;
    }

    var gpa = std.heap.GeneralPurposeAllocator(GPAConfig){};
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();

    const odata = try OData.init(&allocator);
    defer odata.close();

    const ofile = try MachOFile.load(&args, odata);
    try ofile.parse();
    defer ofile.close();

    const stats = try ofile.file.stat();
    const raw_slice = try allocator.alloc(u8, stats.size);
    defer allocator.free(raw_slice);

    try ofile.dump_all_raw(raw_slice);

    var omap = try OMap.init(&ofile, odata, raw_slice, &allocator);
    defer omap.close();

    try omap.map();

    const int: usize = @intFromPtr(omap.entry_text);
    const add: usize = int + odata.entrypoint_cmd.entryoff;
    const to_ptr: [*]u8 = @ptrFromInt(add);
    std.debug.print("\nentryoff: 0x{x}\nentry_text: {*}\nint: {x}\nadd: {x}\nto_ptr @ {*}...\n", .{
        odata.entrypoint_cmd.entryoff,
        omap.entry_text,
        int,
        add,
        to_ptr,
    });

    const jump: *const fn () void = @alignCast(@ptrCast(to_ptr));
    jump();

    std.debug.print("So far, so good!\n", .{});

    // printer.segment_cmds(odata);
}
