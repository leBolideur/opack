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
    filepath: [:0]const u8,
    file: std.fs.File,
    reader: Reader,

    odata: *OData,

    pub fn load(args: *std.process.ArgIteratorPosix, odata: *OData) ParserError!MachOFile {
        _ = args.skip();
        const filepath = args.next().?;
        const file = std.fs.cwd().openFile(filepath, .{}) catch |err| {
            try stderr.print("Error loading file: {!}\n", .{err});
            return FileError.OpenFileError;
        };

        return MachOFile{
            .filepath = filepath,
            .file = file,
            .reader = file.reader(),
            .odata = odata,
        };
    }

    pub fn parse(self: MachOFile) ParserError!void {
        const header = try self.dump_header();
        try self.list_load_commands(&header);
        // self.file.close();
    }

    pub fn dump_all_raw(self: MachOFile, buffer: []u8) !void {
        try self.file.seekTo(0);
        _ = try self.reader.readAll(buffer);
        // std.debug.print("All readed: {d}\n", .{bytes_readed});
        try self.file.seekTo(0);
    }

    pub fn dump_header(self: MachOFile) ParserError!macho.mach_header_64 {
        // std.debug.print("Dumping header...\n", .{});
        const header = self.reader.readStruct(macho.mach_header_64) catch return ReadError.ReadHeader;

        if (header.magic != macho.MH_MAGIC_64) {
            try stderr.print("Not a machO64 file\n", .{});
            self.file.close();
            return FormatError.NotMachO64;
        }
        if (header.filetype != macho.MH_EXECUTE) {
            try stderr.print("Dumping header error\n", .{});
            self.file.close();
            return FormatError.NotExecutable;
        }

        self.odata.set_header(header);

        return header;
    }

    pub fn list_load_commands(self: MachOFile, header: *const macho.mach_header_64) ParserError!void {
        // try stdout.print("{d} load commands found\n\n", .{header.ncmds});

        for (0..header.ncmds) |_| {
            const lcmd = self.reader.readStruct(macho.load_command) catch return ReadError.ReadLoadCommand;
            switch (lcmd.cmd) {
                macho.LC.SEGMENT_64 => try self.dump_segment_cmd(),
                macho.LC.MAIN => try self.dump_entrypoint_cmd(),
                macho.LC.SYMTAB => try self.dump_symtab_cmd(),
                else => try self.file.seekBy(lcmd.cmdsize - @sizeOf(macho.load_command)),
            }
        }
    }

    fn dump_symtab_cmd(self: MachOFile) ParserError!void {
        try self.file.seekBy(-@sizeOf(macho.load_command));
        const symtab_cmd = try self.safeReadStruct(macho.symtab_command);

        self.odata.set_symtab_cmd(symtab_cmd);

        const seek_pos_bck = try self.file.getPos();
        defer self.file.seekTo(seek_pos_bck) catch {};

        try self.file.seekTo(symtab_cmd.symoff);
        for (0..symtab_cmd.nsyms) |_| {
            const sym = try self.safeReadStruct(macho.nlist_64);
            try self.odata.add_symtab_entry(sym);
        }
    }

    fn dump_segment_cmd(self: MachOFile) ParserError!void {
        try self.file.seekBy(-@sizeOf(macho.load_command));
        const seg64_cmd = try self.safeReadStruct(macho.segment_command_64);

        const segment_cmd = try self.odata.create_segment_cmd(seg64_cmd);

        for (0..seg64_cmd.nsects) |_| {
            const sect = try self.dump_section();
            try segment_cmd.add_section(sect);
        }
    }

    fn dump_section(self: MachOFile) !macho.section_64 {
        const section = try self.safeReadStruct(macho.section_64);
        return section;
    }

    fn dump_entrypoint_cmd(self: MachOFile) ParserError!void {
        try self.file.seekBy(-@sizeOf(macho.load_command));
        const entrypoint_cmd = try self.safeReadStruct(macho.entry_point_command);
        self.odata.set_entrypoint_cmd(entrypoint_cmd);
    }

    // Used to pick data form file and restore reader
    pub fn pick(self: MachOFile, offset: u64, size: u64, buffer: *[]u8) !void {
        const seek_pos_bck = try self.file.getPos();
        try self.file.seekTo(offset);
        const size_read = try self.reader.read(buffer.*);
        std.debug.print("wanted: {d}\treaded: {d}\n", .{ size, size_read });
        try self.file.seekTo(seek_pos_bck);
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

    pub fn close(self: MachOFile) void {
        self.file.close();
    }
};
