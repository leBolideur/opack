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

        // std.debug.print("sect addr >> {x}\n", .{(sect.?.addr)});
        // std.debug.print("sect offset >> {d}\traw size: {d}\n", .{ sect.?.offset, stats.size });
        // std.debug.print("sect size >> {d}\n", .{(sect.?.size)});

        // try omap.debug_disas(sect_data);

        std.debug.print("\nExecuting...\n\n", .{});
        // std.debug.print(" sect_data @ {*:<15}\n", .{(sect_data)});

        const macho = std.macho;
        const prot = macho.PROT.READ | macho.PROT.WRITE;
        const reajust_prot = macho.PROT.READ | macho.PROT.EXEC;

        const flags = std.os.MAP.ANONYMOUS | std.os.MAP.PRIVATE;
        const map_size: usize = 4096;
        const map = std.os.mmap(null, map_size, prot, flags, -1, 0) catch |err| {
            std.debug.print("mmap full err >>> {!}\n", .{err});
            return;
        };
        defer std.os.munmap(map);

        const fileoff = sect.?.offset;
        const size = sect.?.size;
        const sect_data = raw_slice[fileoff..(fileoff + size)];

        const region = OMap.get_region_slice(map.ptr);
        const dest: []u8 = map[0..map_size];
        std.mem.copy(u8, dest, sect_data);

        std.debug.print("region_ptr @ {*:<15}\n", .{region.ptr});
        std.debug.print("region_len @ {d:<15}\n", .{region.len});
        std.os.mprotect(region, reajust_prot) catch |err| {
            std.debug.print("mprotect full err >>> {!}\n", .{err});
        };

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
