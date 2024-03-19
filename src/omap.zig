const std = @import("std");
const macho = std.macho;

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
        _ = self;
        // const sect = self.odata.get_text_sect();
        // if (sect == null) {
        //     std.debug.print("no __text section!\n", .{});
        //     return;
        // }
    }

    pub fn debug_disas(self: OMap, data: []u8) !void {
        // TODO: pipe stream
        std.debug.print("\nDisassembling {s}...\n", .{self.ofile.filepath});
        var tmp_file = try std.fs.cwd().createFile(".bin", .{ .truncate = true });
        defer tmp_file.close();
        try tmp_file.writeAll(data);

        const size_u64 = comptime @sizeOf(u64);
        var buf: [size_u64]u8 = undefined;
        const entry_offset = try std.fmt.bufPrint(buf[0..], "{}", .{self.odata.entrypoint_cmd.entryoff});

        const argv = [_][]const u8{ "radare2", "-b", "64", "-m", entry_offset, "-qc", "\"pd 10\"", ".bin" };
        var proc = try std.ChildProcess.exec(.{
            .allocator = self.allocator.*,
            .argv = &argv,
        });

        std.debug.print("{s}\n", .{proc.stdout});
        std.debug.print("Err: {s}", .{proc.stderr});

        defer self.allocator.free(proc.stdout);
        defer self.allocator.free(proc.stderr);
    }
};

pub const MapRequest = struct {
    map: []align(page_size) u8,
    map_size: usize,
    region: []align(page_size) u8,

    pub fn ask(size: usize) ?MapRequest {
        const prot = macho.PROT.READ | macho.PROT.WRITE;
        const flags = std.os.MAP.ANONYMOUS | std.os.MAP.PRIVATE;
        const anon_map = std.os.mmap(null, size, prot, flags, -1, 0) catch |err| {
            std.debug.print("mmap err >>> {!}\n", .{err});
            return null;
        };

        const region_slice = MapRequest.get_region_slice(anon_map.ptr);

        return MapRequest{
            .map = anon_map,
            .map_size = size,
            .region = region_slice,
        };
    }

    pub fn write(self: MapRequest, comptime T: type, data: []T) void {
        const sect_data = data[0..data.len];
        const dest: []T = self.map[0..self.map_size];
        std.mem.copy(T, dest, sect_data);
    }

    pub fn mprotect(self: MapRequest, prot: u32) void {
        std.os.mprotect(self.region, prot) catch |err| {
            std.debug.print("mprotect full err >>> {!}\n", .{err});
        };
    }

    fn get_region_slice(addr_ptr: [*]u8) []align(page_size) u8 {
        const ptr_to_int = @intFromPtr(addr_ptr);
        var region: usize = ptr_to_int & ~(page_size - 1);
        var region_ptr: [*]align(page_size) u8 = @ptrFromInt(region);
        const region_slice = region_ptr[0..page_size];

        std.debug.print("region_ptr @ {*:<15}\n", .{region_ptr});
        std.debug.print("region_len @ {d:<15}\n", .{region_slice.len});

        return region_slice;
    }

    pub fn close(self: MapRequest) void {
        std.os.munmap(self.map);
    }
};
