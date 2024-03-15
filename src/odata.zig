const std = @import("std");
const macho = std.macho;

const gpa = @import("gpa.zig").allocator;

const SegmentCmd = struct {
    segment_cmd: ?macho.segment_command_64,
    sections: std.ArrayList(macho.section_64),

    pub fn init() SegmentCmd {
        return SegmentCmd{
            .segment_cmd = undefined,
            .sections = std.ArrayList(macho.section_64).init(gpa),
        };
    }
};

pub const OData = struct {
    header: *macho.mach_header_64,
    segment_cmds: std.ArrayList(SegmentCmd),

    pub fn init() OData {
        return OData{
            .header = undefined,
            .segment_cmds = std.ArrayList(SegmentCmd).init(gpa),
        };
    }

    pub fn set_header(self: *OData, header: *macho.mach_header_64) void {
        self.header = header;
    }

    pub fn set_segment_cmd(
        self: *OData,
        seg_cmd: *macho.segment_command_64,
        sections: *std.ArrayList(macho.section_64),
    ) void {
        const seg_struct = SegmentCmd{
            .segment_cmd = seg_cmd,
            .sections = sections,
        };

        self.segment_cmds.append(seg_struct);
    }
};
