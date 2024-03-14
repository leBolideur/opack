const std = @import("std");
const macho = std.macho;

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

const Reader = std.fs.File.Reader;

const FormatError = error{ NotMachO64, NotExecutable };
const ReadError = error{ ReadHeader, ReadLoadCommand };
const FileError = error{OpenFileError};
const ParserError = error{SegCmdBoundary};
const DumperError = anyerror || FormatError || ReadError || FileError || ParserError;

pub const MachOFile64 = struct {
    allocator: std.mem.Allocator,

    filepath: [:0]const u8,
    file: std.fs.File,
    reader: Reader,

    header: macho.mach_header_64,

    pub fn close(self: *MachOFile64) void {
        self.file.close();
        self.allocator.destroy(self);
    }

    pub fn load(args: *std.process.ArgIteratorPosix, allocator: std.mem.Allocator) DumperError!*MachOFile64 {
        _ = args.skip();
        const filepath = args.next().?;
        const file = std.fs.cwd().openFile(filepath, .{}) catch |err| {
            try stderr.print("Error loading file: {!}\n", .{err});
            return FileError.OpenFileError;
        };

        var ptr = try allocator.create(MachOFile64);

        ptr.* = MachOFile64{
            .allocator = allocator,
            .filepath = filepath,
            .file = file,
            .reader = file.reader(),
            .header = undefined,
        };

        return ptr;
    }

    pub fn dump_header(self: *MachOFile64) DumperError!void {
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

    pub fn list_load_commands(self: MachOFile64) DumperError!void {
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

    fn dump_segment_cmd(self: MachOFile64) DumperError!void {
        const seg64_cmd = try self.safeReadStruct(macho.segment_command_64);
        try self.file.seekBy(seg64_cmd.nsects * @sizeOf(macho.section_64));

        std.debug.print("SEGMENT_64   SegName: {s: >20}\tNsects: {d}\tcmdsize: {d}\n", .{
            seg64_cmd.segname,
            seg64_cmd.nsects,
            seg64_cmd.cmdsize,
        });
    }

    fn dump_entrypoint_cmd(self: MachOFile64) DumperError!void {
        const main_cmd = try self.safeReadStruct(macho.entry_point_command);
        std.debug.print("MAIN         Entry: {d: >11}\n", .{main_cmd.entryoff});
    }

    fn safeReadStruct(self: MachOFile64, comptime T: type) !T {
        try self.file.seekBy(-@sizeOf(macho.load_command));

        const start_cursor = try self.file.getPos();
        const struct_readed = self.reader.readStruct(T) catch return ReadError.ReadLoadCommand;
        const end_cursor = try self.file.getPos();

        try MachOFile64.check_boundary(start_cursor, end_cursor, @sizeOf(T));

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
