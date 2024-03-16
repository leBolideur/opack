const std = @import("std");

const MachOFile = @import("parser.zig").MachOFile;
const OData = @import("odata.zig").OData;

const GPAConfig = .{ .verbose_log = false };

pub const OPacker = struct {
    // odata: *OData,
    // gpa_alloc: *std.mem.Allocator,
    // gpa: std.heap.GeneralPurposeAllocator(GPAConfig),

    pub fn init(args: *std.process.ArgIteratorPosix) !void {
        var gpa = std.heap.GeneralPurposeAllocator(GPAConfig){};
        // defer _ = gpa.deinit();
        var allocator = gpa.allocator();

        var odata_ptr = try OData.init(&allocator);
        defer allocator.destroy(odata_ptr);

        const ofile = try MachOFile.load(args, odata_ptr);
        try ofile.parse();

        OPacker.print_test(odata_ptr);

        odata_ptr.close();

        // return OPacker{
        //     .odata = odata_ptr,
        //     // .gpa_alloc = &allocator,
        //     // .gpa = gpa,
        // };
    }

    pub fn print_test(odata: *OData) void {
        for (odata.segment_cmds.items) |seg| {
            std.debug.print("segname: {s}\n", .{seg.segment_cmd.segname});
            if (seg.sections) |sections| {
                for (sections.items) |sec| {
                    std.debug.print("\t secname: {s}\n", .{sec.sectname});
                }
            }
        }
        std.debug.print("MAIN     Entry: {x: >10}\n", .{odata.entrypoint_cmd.entryoff});
    }

    pub fn close(self: OPacker) void {
        _ = self;
        // self.odata.close();
        // _ = self.gpa.deinit();
    }
};
