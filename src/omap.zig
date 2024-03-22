const std = @import("std");
const macho = std.macho;

const OFile = @import("parser.zig").MachOFile;
const odata_import = @import("odata.zig");
const OData = odata_import.OData;
const SegmentType = odata_import.SegmentType;

const page_size: usize = 0x4000; // TODO: Find a way to get system page_size

const MapRequestError = error{MmapFailed};
const MapperError = anyerror || MapRequestError;

fn pause() !void {
    var input: [1]u8 = undefined;
    const stdin = std.io.getStdIn().reader();
    _ = try stdin.readUntilDelimiter(&input, '\n');
}

pub const OMap = struct {
    ofile: *const OFile,
    odata: *OData,
    raw_slice: []u8,
    mappings: std.ArrayList(MapRequest),
    base_addr: [*]align(page_size) u8,
    entry_text: [*]align(page_size) u8,

    allocator: *std.mem.Allocator,

    pub fn init(
        ofile: *const OFile,
        odata: *OData,
        raw_slice: []u8,
        allocator: *std.mem.Allocator,
    ) OMap {
        return OMap{
            .ofile = ofile,
            .odata = odata,
            .raw_slice = raw_slice,
            .mappings = std.ArrayList(MapRequest).init(allocator.*),
            .base_addr = undefined,
            .entry_text = undefined,
            .allocator = allocator,
        };
    }

    pub fn map(self: *OMap) !void {
        // std.debug.print("\nMapping...\n", .{});

        for (self.odata.load_cmds.items) |seg| {
            const seg_type = seg.type orelse break;
            _ = switch (seg_type) {
                SegmentType.TEXT => {
                    std.debug.print("__TEXT\n", .{});
                    const section = try seg.get_text_sect();
                    var response = try self.map_segment(section.?, null);
                    response.mprotect(std.macho.PROT.READ | std.macho.PROT.EXEC);

                    const base_int = @intFromPtr(response.map.ptr) + seg.segment_cmd.filesize;
                    self.base_addr = @ptrFromInt(base_int);
                    std.debug.print("base_addr  @ {*}\n", .{self.base_addr});

                    self.entry_text = @ptrCast(response.region.?);
                    std.debug.print("\nWill jump @ {*}...\n", .{response.region.?});
                    self.debug_disas(response.data.?, self.odata.entrypoint_cmd.entryoff) catch {};
                },
                SegmentType.DATA => {
                    std.debug.print("__DATA\n", .{});
                    const section = try seg.get_data_sect();
                    var response = try self.map_segment(section.?, null);
                    std.debug.print("\n__data map    @ {*}\n", .{response.map.ptr});
                    if (response.region != null)
                        std.debug.print("__data region @ {*}\n", .{response.region.?.ptr});

                    const int_data = @intFromPtr(response.map.ptr);
                    const int_base = @intFromPtr(self.base_addr);
                    std.debug.print("offset: {x}\n", .{int_data - int_base});
                    std.debug.print("data: {s}\n", .{response.data.?});

                    self.debug_disas(response.data.?, section.?.offset) catch {};
                },
                SegmentType.Unknown => continue,
            };
        }
    }

    fn map_segment(self: *OMap, section: macho.section_64, request_addr: ?[*]align(page_size) u8) !MapRequest {
        const int = if (request_addr != null) @intFromPtr(request_addr) else null;
        var response = try MapRequest.ask(int, section.size) orelse {
            std.debug.print("Response map_segment: nop!\n", .{});
            return MapRequestError.MmapFailed;
        };
        try self.mappings.append(response);

        const data = self.write_section_data(&response, section, self.raw_slice);

        _ = data;
        // const hex = std.fmt.fmtSliceHexLower(data);
        // std.debug.print("\n------\ndata: {x}\n------\n", .{hex});

        return response;
    }

    pub fn write_section_data(
        self: OMap,
        request: *MapRequest,
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
    data: ?[]u8,

    pub fn ask(addr: ?usize, size: usize) MapRequestError!?MapRequest {
        const prot = macho.PROT.READ | macho.PROT.WRITE;

        // TODO: Ugly as hell... (to avoid comptime related error)
        var flags: u32 = @as(u32, std.os.MAP.ANONYMOUS) | @as(u32, std.os.MAP.PRIVATE);

        var req: ?[*]align(page_size) u8 = null;
        if (addr != null) {
            flags |= @as(u32, std.os.MAP.FIXED);

            const req_aligned = MapRequest.align_low(addr.? + (page_size - 1));

            const addr_ptr: [*]align(page_size) u8 = @ptrFromInt(req_aligned);
            const aligned: []align(page_size) u8 = MapRequest.get_aligned_region_slice(addr_ptr);
            std.debug.print("req_aligned: {x} --> aligned: {*}\n", .{ req_aligned, aligned });

            req = if (addr != null) aligned.ptr else null;
        }

        const anon_map = std.os.mmap(req, size, prot, flags, -1, 0) catch |err| {
            std.debug.print("mmap err >>> {!}\n", .{err});
            return MapRequestError.MmapFailed;
        };

        return MapRequest{
            .map = anon_map,
            .map_size = size,
            .region = null,
            .data = undefined,
        };
    }

    pub fn write(self: *MapRequest, comptime T: type, data: []T) void {
        std.debug.print("Writing...", .{});
        const sect_data = data[0..data.len];
        const dest: []T = self.map[0..self.map_size];
        std.mem.copy(T, dest, sect_data);
        self.data = data;
    }

    pub fn mprotect(self: *MapRequest, prot: u32) void {
        if (self.region == null) {
            self.region = MapRequest.get_aligned_region_slice(self.map.ptr);
        }
        std.debug.print("  mprotect @ {*}...\n", .{self.region.?});
        std.os.mprotect(self.region.?, prot) catch |err| {
            std.debug.print("mprotect err >>> {!}\n", .{err});
        };
    }

    fn get_aligned_region_slice(addr_ptr: [*]u8) []align(page_size) u8 {
        const ptr_to_int = @intFromPtr(addr_ptr);
        var region: usize = ptr_to_int & ~(page_size - 1);
        var region_ptr: [*]align(page_size) u8 = @ptrFromInt(region);
        const region_slice = region_ptr[0..page_size];

        std.debug.print("region_ptr @ {*:<15}\n", .{region_ptr});
        std.debug.print("region_len @ {d:<15}\n", .{region_slice.len});

        return region_slice;
    }

    pub fn align_low(x: usize) usize {
        return (x + page_size - 1) & ~(page_size - 1);
    }

    pub fn close(self: MapRequest) void {
        std.os.munmap(self.map);
    }
};
