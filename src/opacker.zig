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

fn pause() !void {
    var input: [1]u8 = undefined;
    const stdin = std.io.getStdIn().reader();
    _ = try stdin.readUntilDelimiter(&input, '\n');
}

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
        printer.segment_cmds(odata_ptr);
        // printer.symtab(odata_ptr);

        const stats = try ofile.file.stat();
        var raw_slice = try allocator.alloc(u8, stats.size);
        defer allocator.free(raw_slice);

        try ofile.dump_all_raw(raw_slice);

        var omap = OMap.init(&ofile, odata_ptr, raw_slice, &allocator);
        // defer omap.close();

        try omap.map();
        const int: usize = @intFromPtr(omap.entry_text);
        const add: usize = int + 16220; // odata_ptr.entrypoint_cmd.entryoff;
        const to_ptr: [*]u8 = @ptrFromInt(add);
        std.debug.print("\nentryoff: 0x{x}\nentry_text: {*}\nint: {x}\nadd: {x}\nto_ptr @ {*}...\n", .{
            odata_ptr.entrypoint_cmd.entryoff,
            omap.entry_text,
            int,
            add,
            to_ptr,
        });
        const jump: *const fn () void = @alignCast(@ptrCast(to_ptr));
        // const j2: *const fn () void = @alignCast(@ptrCast(omap.entry_text));

        // try pause();
        std.debug.print("\nJumping @ {*}...\n", .{to_ptr});
        // _ = jump;

        jump();

        std.debug.print("\nSo far, so good...\n", .{});
    }
};
