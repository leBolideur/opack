const std = @import("std");
const macho = std.macho;

const OData = @import("odata.zig").OData;

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

const Reader = std.fs.File.Reader;

const FormatError = error{ NotMachO64, NotExecutable };
const ReadError = error{ ReadHeader, ReadLoadCommand, SegCmdBoundary };
const FileError = error{OpenFileError};
const ParserError = anyerror || FormatError || ReadError || FileError;

pub const MachOFile = struct {
    // allocator: *std.mem.Allocator,

    filepath: [:0]const u8,
    file: std.fs.File,
    reader: Reader,

    header: macho.mach_header_64,
    odata: OData,

    pub fn close(self: MachOFile) void {
        self.file.close();
        // self.sections.deinit();
        // self.allocator.destroy(self);
    }

    pub fn load(args: *std.process.ArgIteratorPosix) ParserError!MachOFile {
        _ = args.skip();
        const filepath = args.next().?;
        const file = std.fs.cwd().openFile(filepath, .{}) catch |err| {
            try stderr.print("Error loading file: {!}\n", .{err});
            return FileError.OpenFileError;
        };

        // var ptr = try allocator.create(MachOFile);

        // ptr.* =
        return MachOFile{
            // .allocator = allocator,
            .filepath = filepath,
            .file = file,
            .reader = file.reader(),
            .header = undefined,
            .odata = OData.init(),
            // .sections = std.ArrayList(macho.section_64).init(allocator),
        };
    }

    pub fn parse(self: *MachOFile) ParserError!void {
        // const odata_ptr = try self.allocator.create(OData);
        // odata_ptr.* = OData{};

        // return odata_ptr;

        try self.dump_header();
        self.odata.set_header(&self.header);
    }

    pub fn dump_header(self: *MachOFile) ParserError!void {
        std.debug.print("Dumping header...\n", .{});
        self.header = self.reader.readStruct(macho.mach_header_64) catch return ReadError.ReadHeader;

        if (self.header.magic != macho.MH_MAGIC_64) {
            try stderr.print("Not a machO64 file\n", .{});
            self.close();
            return FormatError.NotMachO64;
        }
        if (self.header.filetype != macho.MH_EXECUTE) {
            try stderr.print("Dumping header error\n", .{});
            self.close();
            return FormatError.NotExecutable;
        }
    }

    pub fn list_load_commands(self: MachOFile) ParserError!void {
        try stdout.print("{d} load commands found\n\n", .{self.header.ncmds});

        for (0..self.header.ncmds) |_| {
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
        // try self.file.seekBy(seg64_cmd.nsects * @sizeOf(macho.section_64));
        for (0..seg64_cmd.nsects) |_| {
            try self.dump_section();
        }
        std.debug.print("SEGMENT_64   SegName: {s: >20}\tNsects: {d}\tcmdsize: {d}\n", .{
            seg64_cmd.segname,
            seg64_cmd.nsects,
            seg64_cmd.cmdsize,
        });
        // for (self.sections.items) |sec| {
        //     std.debug.print("\tSecName: {s}\n", .{sec.sectname});
        // }
    }

    fn dump_section(self: MachOFile) !void {
        _ = try self.safeReadStruct(macho.section_64);
        // try self.sections.append(section);
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
