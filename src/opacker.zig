const std = @import("std");

const MachOFile = @import("parser.zig").MachOFile;
const gpa_alloc = @import("gpa.zig").allocator;

pub const OPacker = struct {
    ofile: *MachOFile,

    pub fn init(args: *std.process.ArgIteratorPosix) !*OPacker {
        var ofile = try MachOFile.load(args);
        try ofile.parse();

        var ptr = try gpa_alloc.create(OPacker);
        ptr.* = OPacker{
            .ofile = ofile,
        };

        return ptr;
    }

    pub fn close(self: *OPacker) void {
        self.ofile.close();
        gpa_alloc.destroy(self);
    }
};
