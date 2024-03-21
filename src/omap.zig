const std = @import("std");
const macho = std.macho;

const OFile = @import("parser.zig").MachOFile;
const odata_import = @import("odata.zig");
const OData = odata_import.OData;
const SegmentType = odata_import.SegmentType;

const page_size: usize = 0x4000; // TODO: Find a way to get system page_size

const MapRequestError = error{MmapFailed};
const MapperError = anyerror || MapRequestError;

pub const OMap = struct {
    ofile: *const OFile,
    odata: *OData,
    raw_file: []u8,
    mappings: std.ArrayList(MapRequest),

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
            .mappings = std.ArrayList(MapRequest).init(allocator.*),
            .allocator = allocator,
        };
    }

    pub fn map(self: *OMap, raw_slice: []u8) !*const fn () void {
        var jmp: *const fn () void = undefined;
        std.debug.print("\nMapping...\n", .{});

        for (self.odata.load_cmds.items) |seg| {
            const seg_type = seg.type orelse break;
            const section_ = switch (seg_type) {
                SegmentType.DATA => try seg.get_data_sect(),
                SegmentType.TEXT => try seg.get_text_sect(),
                SegmentType.Unknown => continue,
            };

            const section: macho.section_64 = section_.?;
            var response = try MapRequest.ask(null, section.size) orelse {
                std.debug.print("Response text_map: nop!\n", .{});
                return MapRequestError.MmapFailed;
            };
            try self.mappings.append(response);

            const data = self.write_section_data(&response, section, raw_slice);
            response.mprotect(std.macho.PROT.READ | std.macho.PROT.EXEC);

            if (seg_type == SegmentType.TEXT) {
                std.debug.print("\nJumping @ 0x{*}...\n", .{response.region.?});
                jmp = @ptrCast(response.region.?);
            }

            self.debug_disas(data, section.addr) catch {};
        }

        return jmp;
    }

    pub fn write_section_data(
        self: OMap,
        request: *const MapRequest,
        data_section: macho.section_64,
        raw_slice: []u8,
    ) []const u8 {
        _ = self;
        const data_fileoff = data_section.offset;
        const data_size = data_section.size;
        const data_sect_raw = raw_slice[data_fileoff..(data_fileoff + data_size)];

        request.write(u8, data_sect_raw);

        return data_sect_raw;
    }

    pub fn debug_disas(self: OMap, data: []const u8, offset: u64) !void {
        // TODO: pipe stream
        std.debug.print("\nDisassembling {s} with offset {?x}...\n", .{ self.ofile.filepath, offset });
        var tmp_file = try std.fs.cwd().createFile(".bin", .{ .truncate = true });
        defer tmp_file.close();
        try tmp_file.writeAll(data);

        const entry_offset = try std.fmt.allocPrint(self.allocator.*, "{d}", .{offset});
        defer self.allocator.free(entry_offset);

        const argv = [_][]const u8{ "radare2", "-b", "64", "-m", entry_offset, "-qc", "\"pd 10\"", ".bin" };
        var proc = try std.ChildProcess.exec(.{
            .allocator = self.allocator.*,
            .argv = &argv,
        });

        std.debug.print("{s}\n", .{proc.stdout});
        // std.debug.print("Err: {s}", .{proc.stderr});

        defer self.allocator.free(proc.stdout);
        defer self.allocator.free(proc.stderr);
    }

    pub fn close(self: OMap) void {
        for (self.mappings.items) |item| {
            item.close();
        }
        self.mappings.deinit();
    }
};

pub const MapRequest = struct {
    map: []align(page_size) u8,
    map_size: usize,
    region: ?[]align(page_size) u8,

    pub fn ask(addr: ?usize, size: usize) MapRequestError!?MapRequest {
        const prot = macho.PROT.READ | macho.PROT.WRITE;

        // TODO: Ugly as hell... (to avoid comptime related error)
        var flags: u32 = @as(u32, std.os.MAP.ANONYMOUS) | @as(u32, std.os.MAP.PRIVATE);

        // FIXME: Allow FIXED
        // if (addr != null) flags |= @as(u32, std.os.MAP.FIXED);

        // const addr_ptr: [*]u8 = @ptrFromInt(addr.?);
        // const aligned: [*]align(page_size) u8 = MapRequest.get_region_slice(addr_ptr);
        // // std.debug.print("\taligned: {*}\n", .{aligned.ptr});
        // const req = if (addr != null) aligned.ptr else null;
        _ = addr;
        const anon_map = std.os.mmap(null, size, prot, flags, -1, 0) catch |err| {
            std.debug.print("mmap err >>> {!}\n", .{err});
            return MapRequestError.MmapFailed;
        };

        return MapRequest{
            .map = anon_map,
            .map_size = size,
            .region = null,
        };
    }

    pub fn write(self: MapRequest, comptime T: type, data: []T) void {
        std.debug.print("Writing...\n", .{});
        const sect_data = data[0..data.len];
        const dest: []T = self.map[0..self.map_size];
        std.mem.copy(T, dest, sect_data);
    }

    pub fn mprotect(self: *MapRequest, prot: u32) void {
        if (self.region == null) {
            self.region = MapRequest.get_region_slice(self.map.ptr);
        }
        std.debug.print("  mprotect @ {*}...\n", .{self.region.?});
        std.os.mprotect(self.region.?, prot) catch |err| {
            std.debug.print("mprotect err >>> {!}\n", .{err});
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
