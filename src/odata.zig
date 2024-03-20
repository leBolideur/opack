const std = @import("std");
const macho = std.macho;

const LoadSegmentCmdError = error{ NoText_Section, NoData_Section };
const ODataError_ = error{
    AllocatorCreate,
    CreateSegmentCmd,
    NoText_Segment,
    NoData_Segment,
};
const ODataError = anyerror || LoadSegmentCmdError || ODataError_;

const LoadSegmentCmd = struct {
    segment_cmd: macho.segment_command_64,
    sections: ?std.ArrayList(macho.section_64),
    segname: []u8,

    gpa_alloc: *const std.mem.Allocator,

    pub fn init(
        segment_cmd: macho.segment_command_64,
        gpa_alloc: *const std.mem.Allocator,
    ) !*LoadSegmentCmd {
        const segname = LoadSegmentCmd.sliceUntilZero(&segment_cmd.segname);

        var segname_ptr = try gpa_alloc.alloc(u8, segname.len);
        std.mem.copy(u8, segname_ptr, segname);

        const ptr = try gpa_alloc.create(LoadSegmentCmd);
        ptr.* = LoadSegmentCmd{
            .segment_cmd = segment_cmd,
            .sections = null,
            .segname = segname_ptr,
            .gpa_alloc = gpa_alloc,
        };

        return ptr;
    }

    pub fn add_section(self: *LoadSegmentCmd, section: macho.section_64) !void {
        if (self.sections == null) {
            self.sections = std.ArrayList(macho.section_64).init(self.gpa_alloc.*);
        }
        if (self.sections) |*sections| try sections.append(section);
    }

    // Used in printer but is it really usefull ?
    pub fn vmem_size(self: *LoadSegmentCmd) u64 {
        return self.segment_cmd.vmaddr + self.segment_cmd.vmsize;
    }

    // TODO: Refactor with get_section_by_name
    pub fn get_text_sect(self: *LoadSegmentCmd) ODataError!?macho.section_64 {
        for (self.sections.?.items) |sect| {
            const sectname = LoadSegmentCmd.sliceUntilZero(&sect.sectname);
            if (std.mem.eql(u8, sectname, "__text")) {
                return sect;
            }
        }

        return LoadSegmentCmdError.NoText_Section;
    }

    // TODO: Refactor with get_section_by_name
    pub fn get_data_sect(self: *LoadSegmentCmd) ODataError!?macho.section_64 {
        for (self.sections.?.items) |sect| {
            const sectname = LoadSegmentCmd.sliceUntilZero(&sect.sectname);
            if (std.mem.eql(u8, sectname, "__data")) {
                return sect;
            }
        }

        return LoadSegmentCmdError.NoData_Section;
    }

    pub fn close(self: *const LoadSegmentCmd) void {
        if (self.sections) |sections| sections.deinit();
        self.gpa_alloc.free(self.segname);
        self.gpa_alloc.destroy(self);
    }

    fn sliceUntilZero(arr: *const [16]u8) []const u8 {
        for (arr, 0..) |byte, index| {
            if (byte == 0) {
                return arr[0..index];
            }
        }
        return arr[0..];
    }
};

pub const OData = struct {
    header: macho.mach_header_64,
    load_cmds: std.ArrayList(*LoadSegmentCmd),
    entrypoint_cmd: macho.entry_point_command,

    gpa_alloc: *const std.mem.Allocator,

    pub fn init(gpa_alloc: *std.mem.Allocator) !*OData {
        const ptr = gpa_alloc.create(OData) catch return ODataError.AllocatorCreateError;

        ptr.* = OData{
            .header = undefined,
            .load_cmds = std.ArrayList(*LoadSegmentCmd).init(gpa_alloc.*),
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
    ) !*LoadSegmentCmd {
        const seg_struct: *LoadSegmentCmd = try LoadSegmentCmd.init(seg_cmd, self.gpa_alloc);
        try self.load_cmds.append(seg_struct);
        return seg_struct;
    }

    pub fn get_textseg_cmd(self: *OData) ?*macho.segment_command_64 {
        for (self.load_cmds.items) |cmd| {
            if (std.mem.eql(u8, cmd.segname, "__TEXT")) {
                return &cmd.segment_cmd;
            }
        }

        return null;
    }

    // TODO: Refactor with get_segment_section_by_name
    pub fn get_text_sect(self: *OData) ODataError!?macho.section_64 {
        for (self.load_cmds.items) |cmd| {
            if (std.mem.eql(u8, cmd.segname, "__TEXT")) {
                const sect = cmd.get_text_sect();
                return sect;
            }
        }

        return ODataError_.NoText_Segment;
    }

    // TODO: Refactor with get_segment_section_by_name
    pub fn get_data_sect(self: *OData) ODataError!?macho.section_64 {
        for (self.load_cmds.items) |cmd| {
            if (std.mem.eql(u8, cmd.segname, "__DATA")) {
                const sect = cmd.get_data_sect();
                return sect;
            }
        }

        return ODataError_.NoData_Segment;
    }

    pub fn close(self: *OData) void {
        for (self.load_cmds.items) |item| {
            item.close();
        }

        self.load_cmds.deinit();
        self.gpa_alloc.destroy(self);
    }
};
