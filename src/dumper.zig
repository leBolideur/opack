const std = @import("std");
const macho = std.macho;

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

const Reader = std.fs.File.Reader;

const FormatError = error{ NotMachO64, NotExecutable };
const ReadError = error{ ReadHeader, ReadLoadCommand };
const FileError = error{OpenFileError};
const DumperError = anyerror || FormatError || ReadError || FileError;

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

        ptr.* = MachOFile64{ .allocator = allocator, .filepath = filepath, .file = file, .reader = file.reader(), .header = undefined };

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
        std.debug.print("magic: {x}\n", .{self.header.magic});
    }

    pub fn list_load_commands(self: *MachOFile64) DumperError!void {
        try stdout.print("{d} load commands found\n", .{self.header.ncmds});
        for (0..self.header.ncmds) |_| {
            const lcmd = self.reader.readStruct(macho.load_command) catch return ReadError.ReadLoadCommand;
            std.debug.print("{d}", .{lcmd.cmd});
        }
    }
};
