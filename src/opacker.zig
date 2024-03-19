const std = @import("std");

const MachOFile = @import("parser.zig").MachOFile;
const OData = @import("odata.zig").OData;
const printer = @import("printer.zig");
const OMap = @import("omap.zig").OMap;

const GPAConfig = .{ .verbose_log = false };

pub const OPacker = struct {
    // odata: *OData,
    // gpa_alloc: *std.mem.Allocator,
    // gpa: std.heap.GeneralPurposeAllocator(GPAConfig),

    pub fn init(args: *std.process.ArgIteratorPosix) !void {
        var gpa = std.heap.GeneralPurposeAllocator(GPAConfig){};
        defer _ = gpa.deinit();

        var allocator = gpa.allocator();

        var odata_ptr = try OData.init(&allocator);
        defer odata_ptr.close();

        const ofile = try MachOFile.load(args, odata_ptr);
        defer ofile.close();

        const stats = try ofile.file.stat();

        var raw_slice = try allocator.alloc(u8, stats.size);
        defer allocator.free(raw_slice);

        try ofile.dump_all_raw(raw_slice);
        std.debug.print("\nWhere is raw_ptr: {*}\n", .{(raw_slice.ptr)});

        try ofile.parse();

        const omap = OMap.init(&ofile, odata_ptr, raw_slice, &allocator);
        omap.map();

        printer.print_test(odata_ptr);

        const sect = odata_ptr.get_text_sect();
        if (sect == null) {
            std.debug.print("no __text section!\n", .{});
            return;
        }

        std.debug.print("sect addr >> {x}\n", .{(sect.?.addr)});
        std.debug.print("sect offset >> {d}\traw size: {d}\n", .{ sect.?.offset, stats.size });
        std.debug.print("sect size >> {d}\n", .{(sect.?.size)});

        const fileoff = sect.?.offset;
        const size = sect.?.size;
        const sect_data = raw_slice[fileoff..(fileoff + size)];

        // try omap.debug_disas(sect_data);

        std.debug.print("\nExecuting...\n\n", .{});
        std.debug.print(" sect_data @ {*:<15}\n", .{(sect_data)});

        const region_slice = OMap.get_region_slice(sect_data.ptr);

        // try pause();
        const macho = std.macho;
        const prot = macho.PROT.READ | macho.PROT.WRITE; // | macho.PROT.EXEC;
        std.os.mprotect(region_slice, prot) catch |err| {
            std.debug.print("mprotect err >>> {!}\n", .{err});
        };
        // try pause();

        // std.debug.print("\nJumping @ 0x{*}...\n", .{sect_data});
        // const jmp: *const fn () void = @ptrCast(region_slice.ptr);
        // jmp();

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
