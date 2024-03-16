const std = @import("std");

const MachOFile = @import("parser.zig").MachOFile;
const OData = @import("odata.zig").OData;
const gpa_alloc = @import("gpa.zig").allocator;

pub const OPacker = struct {
    odata: *OData,

    pub fn init(args: *std.process.ArgIteratorPosix) !OPacker {
        var ofile = try MachOFile.load(args);
        const odata = try ofile.parse();

        for (odata.segment_cmds.items) |seg| {
            std.debug.print("segname: {s}\n", .{seg.segment_cmd.segname});
            for (seg.sections.items) |sec| {
                std.debug.print("\tsecname: {s}\n", .{sec.sectname});
            }
        }
        std.debug.print("MAIN    Entry: {x: >10}\n", .{odata.entrypoint_cmd.entryoff});

        return OPacker{
            .odata = odata,
        };
    }

    pub fn close(self: *OPacker) void {
        self.odata.close();
    }
};
