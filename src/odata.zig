const std = @import("std");
const macho = std.macho;

const gpa_alloc = @import("gpa.zig").allocator;

const SegmentCmd = struct {
    segment_cmd: macho.segment_command_64,
    sections: std.ArrayList(macho.section_64),

    pub fn init(segment_cmd: macho.segment_command_64, sections: std.ArrayList(macho.section_64)) !*SegmentCmd {
        var ptr = try gpa_alloc.create(SegmentCmd);
        ptr.* = SegmentCmd{
            .segment_cmd = segment_cmd,
            .sections = sections,
        };

        return ptr;
    }

    pub fn close(self: *const SegmentCmd) void {
        self.sections.deinit();
        gpa_alloc.destroy(self);
    }
};

pub const OData = struct {
    header: macho.mach_header_64,
    segment_cmds: std.ArrayList(*SegmentCmd),
    entrypoint_cmd: macho.entry_point_command,

    pub fn init() !*OData {
        var ptr = try gpa_alloc.create(OData);
        ptr.* = OData{
            .header = undefined,
            .segment_cmds = std.ArrayList(*SegmentCmd).init(gpa_alloc),
            .entrypoint_cmd = undefined,
        };

        return ptr;
    }

    pub fn set_header(self: *OData, header: macho.mach_header_64) void {
        self.header = header;
    }

    pub fn set_entrypoint_cmd(self: *OData, entrypoint_cmd: macho.entry_point_command) void {
        self.entrypoint_cmd = entrypoint_cmd;
    }

    pub fn set_segment_cmd(
        self: *OData,
        seg_cmd: macho.segment_command_64,
        sections: std.ArrayList(macho.section_64),
    ) !void {
        const seg_struct: *SegmentCmd = try SegmentCmd.init(seg_cmd, sections);
        try self.segment_cmds.append(seg_struct);
    }

    pub fn close(self: *OData) void {
        for (self.segment_cmds.items) |item| {
            item.close();
        }

        self.segment_cmds.deinit();
        gpa_alloc.destroy(self);
    }
};
