const std = @import("std");
const macho = std.macho;

const OData = @import("odata.zig").OData;
const gpa_alloc = @import("gpa.zig").allocator;

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

const Reader = std.fs.File.Reader;

const FormatError = error{ NotMachO64, NotExecutable };
const ReadError = error{ ReadHeader, ReadLoadCommand, SegCmdBoundary };
const FileError = error{OpenFileError};
const ParserError = anyerror || FormatError || ReadError || FileError;

pub const MachOFile = struct {
    filepath: [:0]const u8,
    file: std.fs.File,
    reader: Reader,

    odata: *OData,

    pub fn close(self: *MachOFile) void {
        for (self.odata.segment_cmds.items) |seg| {
            std.debug.print("segname: {s}\n", .{seg.segment_cmd.segname});
            std.debug.print("typeof sects: {?}\n", .{@TypeOf(seg.sections)});
            for (seg.sections.items) |sec| {
                std.debug.print("\tsecname: {s}\n", .{sec.sectname});
            }
        }
        self.file.close();
        self.odata.close();
        gpa_alloc.destroy(self);
    }

    pub fn load(args: *std.process.ArgIteratorPosix) ParserError!*MachOFile {
        _ = args.skip();
        const filepath = args.next().?;
        const file = std.fs.cwd().openFile(filepath, .{}) catch |err| {
            try stderr.print("Error loading file: {!}\n", .{err});
            return FileError.OpenFileError;
        };

        var ptr = try gpa_alloc.create(MachOFile);

        ptr.* = MachOFile{
            .filepath = filepath,
            .file = file,
            .reader = file.reader(),
            .odata = try OData.init(),
        };

        return ptr;
    }

    pub fn parse(self: *MachOFile) ParserError!void {
        const header = try self.dump_header();
        try self.list_load_commands(&header);
    }

    pub fn dump_header(self: *MachOFile) ParserError!macho.mach_header_64 {
        std.debug.print("Dumping header...\n", .{});
        const header = self.reader.readStruct(macho.mach_header_64) catch return ReadError.ReadHeader;

        if (header.magic != macho.MH_MAGIC_64) {
            try stderr.print("Not a machO64 file\n", .{});
            self.close();
            return FormatError.NotMachO64;
        }
        if (header.filetype != macho.MH_EXECUTE) {
            try stderr.print("Dumping header error\n", .{});
            self.close();
            return FormatError.NotExecutable;
        }

        self.odata.set_header(header);

        return header;
    }

    pub fn list_load_commands(self: MachOFile, header: *const macho.mach_header_64) ParserError!void {
        try stdout.print("{d} load commands found\n\n", .{header.ncmds});

        for (0..header.ncmds) |_| {
            const lcmd = self.reader.readStruct(macho.load_command) catch return ReadError.ReadLoadCommand;
            switch (lcmd.cmd) {
                macho.LC.SEGMENT_64 => try self.dump_segment_cmd(),
                macho.LC.MAIN => try self.dump_entrypoint_cmd(),
                else => try self.file.seekBy(lcmd.cmdsize - @sizeOf(macho.load_command)),
            }
        }
    }

    fn dump_segment_cmd(self: MachOFile) ParserError!void {
        try self.file.seekBy(-@sizeOf(macho.load_command));
        const seg64_cmd = try self.safeReadStruct(macho.segment_command_64);

        const sections = std.ArrayList(macho.section_64).init(gpa_alloc);
        // defer sections.deinit();

        for (0..seg64_cmd.nsects) |_| {
            const sect = try self.dump_section();
            try sections.append(sect);
        }
        try self.odata.set_segment_cmd(seg64_cmd, sections);

        std.debug.print("SEGMENT_64   SegName: {s: >20}\tNsects: {d}\tcmdsize: {d}\n", .{
            seg64_cmd.segname,
            seg64_cmd.nsects,
            seg64_cmd.cmdsize,
        });
        // for (sections.items) |sec| {
        //     std.debug.print("\tSecName: {s}\n", .{sec.sectname});
        // }
    }

    fn dump_section(self: MachOFile) !macho.section_64 {
        const section = try self.safeReadStruct(macho.section_64);
        return section;
    }

    fn dump_entrypoint_cmd(self: MachOFile) ParserError!void {
        try self.file.seekBy(-@sizeOf(macho.load_command));
        const main_cmd = try self.safeReadStruct(macho.entry_point_command);
        std.debug.print("MAIN         Entry: {x: >10}\n", .{main_cmd.entryoff});
    }

    fn safeReadStruct(self: MachOFile, comptime T: type) !T {
        const start_cursor = try self.file.getPos();
        const struct_readed = self.reader.readStruct(T) catch return ReadError.ReadLoadCommand;
        const end_cursor = try self.file.getPos();

        try MachOFile.check_boundary(start_cursor, end_cursor, @sizeOf(T));

        return struct_readed;
    }

    fn check_boundary(cursor_start: u64, cursor_end: u64, expect_size: u64) ParserError!void {
        const diff = cursor_end - cursor_start;
        if (diff != expect_size) {
            std.debug.print("\nBOUNDARY\t\tbefore: {d}\tafter: {d}\tdiff: {d}\tsizeOf: {d}\n", .{
                cursor_start,
                cursor_end,
                diff,
                expect_size,
            });
            return ParserError.SegCmdBoundary;
        }
    }
};
