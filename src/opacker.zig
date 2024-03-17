const std = @import("std");

const MachOFile = @import("parser.zig").MachOFile;
const OData = @import("odata.zig").OData;
const printer = @import("printer.zig");

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
        try ofile.parse();

        printer.print_test(odata_ptr);
        const macho = std.macho;
        const prot = macho.PROT.WRITE & macho.PROT.EXEC;
        const text_lcmd = odata_ptr.get_textseg_cmd();
        if (text_lcmd == null) {
            std.debug.print("no __TEXT segment load cmd!\n", .{});
            return;
        }
        std.debug.print("cmd size: {?}\n", .{(text_lcmd.?.vmsize)});
        const page_ptr = try std.os.mmap(
            null, // std.mem.asBytes(text_lcmd.?.vmaddr),
            @as(usize, text_lcmd.?.vmsize),
            prot,
            std.os.MAP.ANONYMOUS | std.os.MAP.PRIVATE,
            -1,
            0,
        );
        defer std.os.munmap(page_ptr);

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
