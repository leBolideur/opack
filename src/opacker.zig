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

        const stats = try ofile.file.stat();
        var raw_slice = try allocator.alloc(u8, stats.size);
        defer allocator.free(raw_slice);

        try ofile.dump_all_raw(raw_slice);
        // std.debug.print("\nWhere is raw_ptr: {*}\n", .{(raw_slice.ptr)});

        printer.print_debug(odata_ptr);

        var omap = OMap.init(&ofile, odata_ptr, raw_slice, &allocator);
        defer omap.close();

        const jump: *const fn () void = try omap.map(raw_slice);

        std.debug.print("\nJumping...\n", .{});
        jump();

        // ---------- init end -----------

        // const text_section_ = try odata_ptr.get_text_sect();
        // if (text_section_ == null) {
        //     std.debug.print("no __text section!\n", .{});
        // }
        // const text_section = text_section_.?;
        // _ = text_section;

        // const data_section_ = odata_ptr.get_data_sect() catch null;
        // if (data_section_ == null) {
        //     std.debug.print("no __data section!\n", .{});
        // } else {
        //     const data_section = data_section_.?;
        //     const data_region = try MapRequest.ask(data_section.addr, data_section.size) orelse {
        //         std.debug.print("Response data_map: nop!\n", .{});
        //         return PackerError.MmapFailed;
        //     };
        //     omap.write_section_data(&data_region, data_section, raw_slice);
        //     defer data_region.close();
        // }

        // ------ __text --------
        // var text_region = try MapRequest.ask(null, text_section.size) orelse {
        //     std.debug.print("Response text_map: nop!\n", .{});
        //     return PackerError.MmapFailed;
        // };
        // defer text_region.close();

        // omap.write_section_data(&text_region, text_section, raw_slice);
        // text_region.mprotect(std.macho.PROT.READ | std.macho.PROT.EXEC);

        // std.debug.print("\nJumping @ 0x{*}...\n", .{text_region.region.?});
        // const jmp: *const fn () void = @ptrCast(text_region.region.?);
        // {
        //     jmp();
        // }

        std.debug.print("\nSo far, so good...\n", .{});
    }
};

fn pause() !void {
    var input: [1]u8 = undefined;
    const stdin = std.io.getStdIn().reader();
    _ = try stdin.readUntilDelimiter(&input, '\n');
}
