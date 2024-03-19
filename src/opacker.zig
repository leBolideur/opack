const std = @import("std");

const MachOFile = @import("parser.zig").MachOFile;
const OData = @import("odata.zig").OData;
const printer = @import("printer.zig");

const omap_import = @import("omap.zig");
const OMap = omap_import.OMap;
const MapRequest = omap_import.MapRequest;

const GPAConfig = .{ .verbose_log = false };

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

        const stats = try ofile.file.stat();
        var raw_slice = try allocator.alloc(u8, stats.size);
        defer allocator.free(raw_slice);

        try ofile.dump_all_raw(raw_slice);
        // std.debug.print("\nWhere is raw_ptr: {*}\n", .{(raw_slice.ptr)});

        printer.print_debug(odata_ptr);

        const sect = odata_ptr.get_text_sect();
        if (sect == null) {
            std.debug.print("no __text section!\n", .{});
            return;
        }

        std.debug.print("\nMapping...\n\n", .{});

        const request = MapRequest.ask(4096);
        if (request == null) {
            std.debug.print("Response: nop!\n", .{});
        }
        defer request.?.close();

        const fileoff = sect.?.offset;
        const size = sect.?.size;
        const sect_data = raw_slice[fileoff..(fileoff + size)];

        const region = request.?.region;
        request.?.write(u8, sect_data);
        request.?.mprotect(std.macho.PROT.READ | std.macho.PROT.EXEC);

        std.debug.print("\nJumping @ 0x{*}...\n", .{region.ptr});
        const jmp: *const fn () void = @ptrCast(region.ptr);
        jmp();

        std.debug.print("\nSo far, so good...\n", .{});

        // return OPacker{
        //     .odata = odata_ptr,
        //     // .gpa_alloc = &allocator,
        //     // .gpa = gpa,
        // };
    }

    pub fn close(self: OPacker) void {
        _ = self;
        // self.odata.close();
        // _ = self.gpa.deinit();
    }
};

fn pause() !void {
    var input: [1]u8 = undefined;
    const stdin = std.io.getStdIn().reader();
    _ = try stdin.readUntilDelimiter(&input, '\n');
}
