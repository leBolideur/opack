const std = @import("std");
const macho = std.macho;

const SegmentCmd = struct {
    segment_cmd: macho.segment_command_64,
    sections: ?std.ArrayList(macho.section_64),

    gpa_alloc: *const std.mem.Allocator,

    pub fn init(
        segment_cmd: macho.segment_command_64,
        gpa_alloc: *const std.mem.Allocator,
    ) !*SegmentCmd {
        const ptr = try gpa_alloc.create(SegmentCmd);
        ptr.* = SegmentCmd{
            .segment_cmd = segment_cmd,
            .sections = null,
            .gpa_alloc = gpa_alloc,
        };

        return ptr;
    }

    pub fn add_section(self: *SegmentCmd, section: macho.section_64) !void {
        if (self.sections == null) {
            self.sections = std.ArrayList(macho.section_64).init(self.gpa_alloc.*);
        }
        if (self.sections) |*sections| try sections.append(section);
    }

    pub fn close(self: *const SegmentCmd) void {
        if (self.sections) |sections| sections.deinit();
        self.gpa_alloc.destroy(self);
    }
};

pub const OData = struct {
    header: macho.mach_header_64,
    segment_cmds: std.ArrayList(*SegmentCmd),
    entrypoint_cmd: macho.entry_point_command,

    gpa_alloc: *const std.mem.Allocator,

    pub fn init(gpa_alloc: *std.mem.Allocator) !*OData {
        const ptr = try gpa_alloc.create(OData);

        ptr.* = OData{
            .header = undefined,
            .segment_cmds = std.ArrayList(*SegmentCmd).init(gpa_alloc.*),
            .entrypoint_cmd = undefined,
            .gpa_alloc = gpa_alloc,
        };

        return ptr;
    }

    pub fn set_header(self: *OData, header: macho.mach_header_64) void {
        self.header = header;
    }

    pub fn set_entrypoint_cmd(self: *OData, entrypoint_cmd: macho.entry_point_command) void {
        self.entrypoint_cmd = entrypoint_cmd;
    }

    pub fn create_segment_cmd(
        self: *OData,
        seg_cmd: macho.segment_command_64,
    ) !*SegmentCmd {
        const seg_struct: *SegmentCmd = try SegmentCmd.init(seg_cmd, self.gpa_alloc);
        try self.segment_cmds.append(seg_struct);
        return seg_struct;
    }

    pub fn close(self: *OData) void {
        for (self.segment_cmds.items) |item| {
            item.close();
        }

        self.segment_cmds.deinit();
        self.gpa_alloc.destroy(self);
    }
};
