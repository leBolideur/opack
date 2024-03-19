const std = @import("std");

const OFile = @import("parser.zig").MachOFile;
const OData = @import("odata.zig").OData;

const page_size: usize = 0x4000; // TODO: Find a way to get system page_size

pub const OMap = struct {
    ofile: *const OFile,
    odata: *OData,
    raw_file: []u8,

    allocator: *std.mem.Allocator,

    pub fn init(
        ofile: *const OFile,
        odata: *OData,
        raw_file: []u8,
        allocator: *std.mem.Allocator,
    ) OMap {
        return OMap{
            .ofile = ofile,
            .odata = odata,
            .raw_file = raw_file,
            .allocator = allocator,
        };
    }

    pub fn map(self: OMap) void {
        const sect = self.odata.get_text_sect();
        if (sect == null) {
            std.debug.print("no __text section!\n", .{});
            return;
        }
    }

    pub fn debug_disas(self: OMap, data: []u8) !void {
        // TODO: pipe stream
        std.debug.print("\nDisassembling {s}...\n", .{self.ofile.filepath});
        var tmp_file = try std.fs.cwd().createFile(".bin", .{ .truncate = true });
        defer tmp_file.close();
        try tmp_file.writeAll(data);

        const size_u64 = comptime @sizeOf(u64);
        var buf: [size_u64]u8 = undefined;
        const str = try std.fmt.bufPrint(buf[0..], "{}", .{self.odata.entrypoint_cmd.entryoff});

        const argv = [_][]const u8{ "radare2", "-b", "64", "-m", str, "-qc", "\"pd 10\"", ".bin" };
        var proc = try std.ChildProcess.exec(.{
            .allocator = self.allocator.*,
            .argv = &argv,
        });

        std.debug.print("{s}\n", .{proc.stdout});
        std.debug.print("Err: {s}", .{proc.stderr});

        defer self.allocator.free(proc.stdout);
        defer self.allocator.free(proc.stderr);
    }

    pub fn get_region_slice(addr_ptr: [*]u8) []align(page_size) u8 {
        const ptr_to_int = @intFromPtr(addr_ptr);
        var region: usize = ptr_to_int & ~(page_size - 1);
        var region_ptr: [*]align(page_size) u8 = @ptrFromInt(region);
        const region_slice = region_ptr[0..page_size];
        // std.debug.print("typeof region_slice >>> {?}\n", .{@TypeOf(region_slice)});

        // std.debug.print("region_ptr @ {*:<15}\n", .{region_ptr});
        // std.debug.print("region_len @ {d:<15}\n", .{region_slice.len});

        return region_slice;
    }
};
