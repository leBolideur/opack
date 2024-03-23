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

pub const SegmentType = enum { DATA, TEXT, Unknown };

const LoadSegmentCmd = struct {
    segment_cmd: macho.segment_command_64,
    sections: ?std.ArrayList(macho.section_64),
    segname: []const u8,
    type: ?SegmentType,

    gpa_alloc: *const std.mem.Allocator,

    pub fn init(
        segment_cmd: macho.segment_command_64,
        gpa_alloc: *const std.mem.Allocator,
    ) !*LoadSegmentCmd {
        const segname = segment_cmd.segName();

        const ptr = try gpa_alloc.create(LoadSegmentCmd);
        ptr.* = LoadSegmentCmd{
            .segment_cmd = segment_cmd,
            .sections = null,
            .segname = segname,
            .type = @This().get_type_by_name(segname),
            .gpa_alloc = gpa_alloc,
        };

        return ptr;
    }

    fn get_type_by_name(segname: []const u8) SegmentType {
        if (std.mem.eql(u8, segname, "__TEXT")) {
            return SegmentType.TEXT;
        } else if (std.mem.eql(u8, segname, "__DATA")) {
            return SegmentType.DATA;
        }
        return SegmentType.Unknown;
    }

    pub fn add_section(self: *LoadSegmentCmd, section: macho.section_64) !void {
        if (self.sections == null) {
            self.sections = std.ArrayList(macho.section_64).init(self.gpa_alloc.*);
        }
        if (self.sections) |*sections| try sections.append(section);
    }

    // TODO: Refactor with get_section_by_name
    pub fn get_text_sect(self: *LoadSegmentCmd) ODataError!?macho.section_64 {
        for (self.sections.?.items) |sect| {
            if (std.mem.eql(u8, sect.sectName(), "__text")) {
                return sect;
            }
        }

        return LoadSegmentCmdError.NoText_Section;
    }

    // TODO: Refactor with get_section_by_name
    pub fn get_data_sect(self: *LoadSegmentCmd) ODataError!?macho.section_64 {
        for (self.sections.?.items) |sect| {
            if (std.mem.eql(u8, sect.sectName(), "__data")) {
                return sect;
            }
        }

        return LoadSegmentCmdError.NoData_Section;
    }

    pub fn close(self: *const LoadSegmentCmd) void {
        if (self.sections) |sections| sections.deinit();
        self.gpa_alloc.destroy(self);
    }
};

pub const OData = struct {
    header: macho.mach_header_64,
    load_cmds: std.ArrayList(*LoadSegmentCmd),
    entrypoint_cmd: macho.entry_point_command,

    symtab_cmd: macho.symtab_command,
    symtab_entries: std.ArrayList(macho.nlist_64),

    gpa_alloc: *const std.mem.Allocator,

    pub fn init(gpa_alloc: *std.mem.Allocator) !*OData {
        const ptr = gpa_alloc.create(OData) catch return ODataError.AllocatorCreateError;

        ptr.* = OData{
            .header = undefined,
            .load_cmds = std.ArrayList(*LoadSegmentCmd).init(gpa_alloc.*),
            .entrypoint_cmd = undefined,

            .symtab_cmd = undefined,
            .symtab_entries = std.ArrayList(macho.nlist_64).init(gpa_alloc.*),

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

    pub fn set_symtab_cmd(self: *OData, symtab_cmd: macho.symtab_command) void {
        self.symtab_cmd = symtab_cmd;
    }

    pub fn add_symtab_entry(self: *OData, nlist: macho.nlist_64) !void {
        try self.symtab_entries.append(nlist);
    }

    pub fn create_segment_cmd(
        self: *OData,
        seg_cmd: macho.segment_command_64,
    ) !*LoadSegmentCmd {
        const seg_struct: *LoadSegmentCmd = try LoadSegmentCmd.init(seg_cmd, self.gpa_alloc);
        try self.load_cmds.append(seg_struct);
        return seg_struct;
    }

    pub fn get_seg_by_index(self: *OData, index: u8) ?*macho.segment_command_64 {
        for (self.load_cmds.items, 0..) |item, index_| {
            if (index_ == index) return &item.segment_cmd;
        }

        return null;
    }

    pub fn segment_at(self: *OData, offset: u64) ?*macho.segment_command_64 {
        for (self.load_cmds.items) |item| {
            const start = item.segment_cmd.vmaddr;
            const end = item.segment_cmd.vmsize;
            if ((offset >= start) and (offset < end)) {
                return &item.segment_cmd;
            }
        }

        return null;
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
        self.symtab_entries.deinit();
        self.gpa_alloc.destroy(self);
    }
};
