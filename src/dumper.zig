const std = @import("std");
const macho = std.macho;

const Reader = std.fs.File.Reader;

pub const FormatError = error{ NotMachO64, NotExecutable };
const ReadError = error{ReadHeader};
const DumperError = FormatError || ReadError;

pub fn dump_header(reader: *const Reader, header: *macho.mach_header_64) DumperError!void {
    std.debug.print("Dumping header...\n", .{});
    header.* = reader.readStruct(macho.mach_header_64) catch return ReadError.ReadHeader;

    if (header.magic != macho.MH_MAGIC_64) {
        return FormatError.NotMachO64;
    }
    if (header.filetype != macho.MH_EXECUTE) {
        return FormatError.NotExecutable;
    }
}
