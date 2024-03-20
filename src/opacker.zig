const std = @import("std");

const MachOFile = @import("parser.zig").MachOFile;
const OData = @import("odata.zig").OData;
const printer = @import("printer.zig");

const omap_import = @import("omap.zig");
const OMap = omap_import.OMap;
const MapRequest = omap_import.MapRequest;

const GPAConfig = .{ .verbose_log = false };

const MemoryError = error{MmapFailed};
const PackerError = anyerror || MemoryError;

pub const OPacker = struct {
    pub fn init(args: *std.process.ArgIteratorPosix) !void {
        var gpa = std.heap.GeneralPurposeAllocator(GPAConfig){};
        defer _ = gpa.deinit();

        var allocator = gpa.allocator();

        var odata_ptr = try OData.init(&allocator);
        defer odata_ptr.close();

        const ofile = try MachOFile.load(args, odata_ptr);
        try ofile.parse();
        defer ofile.close();
        printer.print_debug(odata_ptr);

        const stats = try ofile.file.stat();
        var raw_slice = try allocator.alloc(u8, stats.size);
        defer allocator.free(raw_slice);

        try ofile.dump_all_raw(raw_slice);

        var omap = OMap.init(&ofile, odata_ptr, raw_slice, &allocator);
        defer omap.close();

        const jump: *const fn () void = try omap.map(raw_slice);

        std.debug.print("\nJumping...\n", .{});
        jump();

        std.debug.print("\nSo far, so good...\n", .{});
    }
};

fn pause() !void {
    var input: [1]u8 = undefined;
    const stdin = std.io.getStdIn().reader();
    _ = try stdin.readUntilDelimiter(&input, '\n');
}
