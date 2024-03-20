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

        // ---------- init end -----------

        const text_section_ = try odata_ptr.get_text_sect();
        if (text_section_ == null) {
            std.debug.print("no __text section!\n", .{});
        }
        const text_section = text_section_.?;

        const data_section_ = try odata_ptr.get_data_sect();
        if (data_section_ == null) {
            std.debug.print("no __data section!\n", .{});
        }
        const data_section = data_section_.?;

        std.debug.print("\nMapping...\n\n", .{});

        const omap = OMap.init(&ofile, odata_ptr, raw_slice, &allocator);
        // ------ __data --------
        const data_region = try MapRequest.ask(data_section.addr, data_section.size) orelse {
            std.debug.print("Response data_map: nop!\n", .{});
            return PackerError.MmapFailed;
        };
        defer data_region.close();

        const data_fileoff = data_section.offset;
        const data_size = data_section.size;
        const data_sect_raw = raw_slice[data_fileoff..(data_fileoff + data_size)];
        try omap.debug_disas(data_sect_raw);

        // const data_region = data_map.region;
        data_region.write(u8, data_sect_raw);
        // data_region.mprotect(std.macho.PROT.READ | std.macho.PROT.EXEC);

        // -
        // -
        // -
        // -

        // ------ __text --------
        const text_region = try MapRequest.ask(text_section.addr, text_section.size) orelse {
            std.debug.print("Response text_map: nop!\n", .{});
            return PackerError.MmapFailed;
        };
        defer text_region.close();

        const text_fileoff = text_section.offset;
        const text_size = text_section.size;
        const text_sect_raw = raw_slice[text_fileoff..(text_fileoff + text_size)];
        try omap.debug_disas(text_sect_raw);
        text_region.write(u8, text_sect_raw);
        text_region.mprotect(std.macho.PROT.READ | std.macho.PROT.EXEC);

        std.debug.print("\nJumping @ 0x{*}...\n", .{text_region.region.ptr});
        const jmp: *const fn () void = @ptrCast(text_region.region.ptr);
        jmp();

        std.debug.print("\nSo far, so good...\n", .{});
    }
};

fn pause() !void {
    var input: [1]u8 = undefined;
    const stdin = std.io.getStdIn().reader();
    _ = try stdin.readUntilDelimiter(&input, '\n');
}
