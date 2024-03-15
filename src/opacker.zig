const std = @import("std");
const MachOFile = @import("parser.zig").MachOFile;

pub const OPacker = struct {
    ofile: MachOFile,

    pub fn init(args: *std.process.ArgIteratorPosix) !OPacker {
        var ofile = try MachOFile.load(args);
        try ofile.parse();
        try ofile.list_load_commands();

        return OPacker{
            .ofile = ofile,
        };
    }

    pub fn close(self: OPacker) void {
        self.ofile.close();
    }
};
