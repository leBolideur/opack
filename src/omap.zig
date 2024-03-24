const std = @import("std");
const macho = std.macho;

const OFile = @import("parser.zig").MachOFile;
const odata_import = @import("odata.zig");
const OData = odata_import.OData;
const LoadSegmentCmd = odata_import.LoadSegmentCmd;
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
            switch (seg_type) {
                SegmentType.TEXT => {
                    std.debug.print("__TEXT\n", .{});
                    const response = try self.map_all_segment(seg, null);
                    response.mprotect(std.macho.PROT.READ | std.macho.PROT.EXEC);

                    const base_int = @intFromPtr(response.map.ptr) + seg.segment_cmd.vmsize;
                    self.base_addr = @ptrFromInt(base_int);

                    // @ptrCast used to convert into pointer... ??
                    self.entry_text = @ptrCast(response.map.ptr);
                },
                SegmentType.DATA => {
                    std.debug.print("\n__DATA\n", .{});
                    const response = try self.map_all_segment(seg, self.base_addr);

                    const int_data = @intFromPtr(response.map.ptr);
                    const int_entry_text = @intFromPtr(self.entry_text);
                    std.debug.print("offset .data - .text: {x}\n", .{int_data - int_entry_text});
                },
                SegmentType.Unknown => continue,
            }
        }
    }

    // fn map_segment(self: *OMap, section: macho.section_64, request_addr: ?[*]align(page_size) u8) !MapRequest {
    //     var response = try MapRequest.ask(request_addr, section.size) orelse {
    //         std.debug.print("Response map_segment: nop!\n", .{});
    //         return MapRequestError.MmapFailed;
    //     };
    //     try self.mappings.append(response);

    //     self.write_section_data(&response, section, self.raw_slice);

    //     return response;
    // }

    fn map_all_segment(
        self: *OMap,
        segment: *LoadSegmentCmd,
        request_addr: ?[*]align(page_size) u8,
    ) !MapRequest {
        const response = try MapRequest.ask(request_addr, segment.segment_cmd.vmsize) orelse {
            std.debug.print("Response map_segment: nop!\n", .{});
            return MapRequestError.MmapFailed;
        };

        try self.mappings.append(response);

        // self.write_segment_data(&response, segment.segment_cmd, self.raw_slice);
        const data_fileoff = segment.segment_cmd.fileoff;
        const data_size = segment.segment_cmd.filesize;
        const data_segment_raw = self.raw_slice[data_fileoff..][0..data_size];
        std.debug.print("data.len: {d}\n", .{data_segment_raw.len});
        response.write(u8, data_segment_raw);

        return response;
    }

    // pub fn write_section_data(
    //     self: OMap,
    //     request: *MapRequest,
    //     data_section: macho.section_64,
    //     raw_slice: []u8,
    // ) void {
    //     _ = self;
    //     const data_fileoff = data_section.offset;
    //     const data_size = data_section.size;
    //     const data_sect_raw = raw_slice[data_fileoff..(data_fileoff + data_size)];

    //     request.write(u8, data_sect_raw);
    // }

    // pub fn write_segment_data(
    //     self: OMap,
    //     request: *const MapRequest,
    //     segment: macho.segment_command_64,
    //     raw_slice: []u8,
    // ) void {
    //     _ = self;
    //     const data_fileoff = segment.fileoff;
    //     const data_size = segment.filesize;
    //     const data_segment_raw = raw_slice[data_fileoff..][0..data_size];
    //     std.debug.print("data.len: {d}\n", .{data_segment_raw.len});

    //     request.write(u8, data_segment_raw);
    // }

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
            std.debug.print("request close @ {*}\n", .{item.map.ptr});
            item.close();
        }
        self.mappings.deinit();
    }
};

pub const MapRequest = struct {
    map: []align(page_size) u8,
    map_size: usize,
    // data: ?[]u8,

    pub fn ask(addr: ?[*]align(page_size) u8, size: usize) MapRequestError!?MapRequest {
        // TODO: Ugly as hell... (to avoid comptime related error)
        var flags: u32 = @as(u32, std.os.MAP.ANONYMOUS) | @as(u32, std.os.MAP.PRIVATE);

        var req: ?[*]align(page_size) u8 = null;
        if (addr != null) {
            pause() catch {};
            flags |= @as(u32, std.os.MAP.FIXED);
            req = MapRequest.align_low(addr.?);
            std.debug.print("requested addr: {*}\taligned addr: {*}\n", .{ addr.?, req.? });
        }

        const prot = macho.PROT.READ | macho.PROT.WRITE;
        const anon_map = std.os.mmap(req, size, prot, flags, -1, 0) catch |err| {
            std.debug.print("mmap err >>> {!}\n", .{err});
            return MapRequestError.MmapFailed;
        };
        std.debug.print("ok for size: {d} @ {*}\n", .{ size, anon_map.ptr });
        pause() catch {};

        return MapRequest{
            .map = anon_map,
            .map_size = size,
            // .data = undefined,
        };
    }

    pub fn write(self: MapRequest, comptime T: type, data: []T) void {
        std.debug.print("Writing {d} bytes @ {*}...\n", .{ data.len, self.map.ptr });

        const sect_data = data[0..data.len];
        const dest: []T = self.map[0..self.map_size];

        std.mem.copy(T, dest, sect_data);
        // self.data = data;
    }

    pub fn mprotect(self: MapRequest, prot: u32) void {
        const ptr_slice = self.map.ptr[0..page_size];
        std.os.mprotect(ptr_slice, prot) catch |err| {
            std.debug.print("mprotect err >>> {!}\n", .{err});
        };
    }

    pub fn align_low(addr: [*]align(page_size) u8) [*]align(page_size) u8 {
        const int = @intFromPtr(addr);
        const ptr: [*]align(page_size) u8 = @ptrFromInt(int & ~(page_size - 1));

        return ptr;
    }

    pub fn close(self: MapRequest) void {
        std.debug.print("request close @ {*}\n", .{self.map.ptr});
        std.os.munmap(self.map);
    }
};
