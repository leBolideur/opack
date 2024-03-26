const std = @import("std");
const macho = std.macho;

const OFile = @import("parser.zig").MachOFile;
const odata_import = @import("odata.zig");
const OData = odata_import.OData;
const LoadSegmentCmd = odata_import.LoadSegmentCmd;
const SegmentType = odata_import.SegmentType;

const page_size: usize = std.mem.page_size;

const MapRequestError = anyerror || error{MmapFailed};
const MapperError = anyerror || MapRequestError;

pub const OMap = struct {
    ofile: *const OFile,
    odata: *OData,
    raw_slice: []u8,
    entry_text: ?[*]align(page_size) u8,
    map_request: *MapRequest,

    allocator: *const std.mem.Allocator,

    pub fn init(
        ofile: *const OFile,
        odata: *OData,
        raw_slice: []u8,
        allocator: *const std.mem.Allocator,
    ) !OMap {
        const segments_total_size = odata.segments_total_size();
        std.debug.print("segments_total_size: {x}\n", .{segments_total_size});
        return OMap{
            .ofile = ofile,
            .odata = odata,
            .raw_slice = raw_slice,
            .entry_text = null,
            .map_request = try MapRequest.init(allocator, segments_total_size),
            .allocator = allocator,
        };
    }

    pub fn map(self: *OMap) !void {
        std.debug.print("Region @ {*}\n", .{self.map_request.global.ptr});
        for (self.odata.load_cmds.items) |seg| {
            switch (seg.type) {
                SegmentType.TEXT => {
                    std.debug.print("__TEXT\n", .{});
                    const response = try self.map_all_segment(seg);
                    self.map_request.mprotect(response, std.macho.PROT.READ | std.macho.PROT.EXEC);

                    self.entry_text = response.ptr;
                },
                SegmentType.DATA => {
                    std.debug.print("\n__DATA\n", .{});
                    const response = try self.map_all_segment(seg);

                    const int_data = @intFromPtr(response.ptr);
                    const int_entry_text = @intFromPtr(self.entry_text);
                    std.debug.print("offset .data - .text: {x}\n", .{int_data - int_entry_text});
                },
                SegmentType.Unknown => {
                    std.debug.print("\nOther: {?}\n", .{seg.type});
                    // _ = try self.map_all_segment(seg);
                },
            }
        }
    }

    fn map_all_segment(
        self: *OMap,
        segment: *LoadSegmentCmd,
    ) ![]align(page_size) u8 {
        const data_fileoff = segment.segment_cmd.fileoff;
        const data_size = segment.segment_cmd.filesize;
        const data_segment_raw = self.raw_slice[data_fileoff..][0..data_size];
        std.debug.print("data_fileoff: {d}\tdata_size: {d}\n", .{ data_fileoff, data_size });

        const response = self.map_request.write(data_segment_raw);

        return response;
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
        self.map_request.close();
    }
};

pub const MapRequest = struct {
    global: []align(page_size) u8,
    // offset: usize,
    cursor: [*]align(page_size) u8,
    allocator: *const std.mem.Allocator,

    pub fn init(allocator: *const std.mem.Allocator, size: usize) !*MapRequest {
        const flags: u32 = std.os.MAP.ANONYMOUS | std.os.MAP.PRIVATE;
        const prot = macho.PROT.READ | macho.PROT.WRITE;
        const anon_map = std.os.mmap(null, size, prot, flags, -1, 0) catch |err| {
            std.debug.print("mmap err >>> {!}\n", .{err});
            return MapRequestError.MmapFailed;
        };

        var ptr = try allocator.create(MapRequest);
        ptr.* = MapRequest{
            .global = anon_map,
            // .offset = 0,
            .cursor = anon_map.ptr,
            .allocator = allocator,
        };

        return ptr;
    }

    pub fn write(self: *MapRequest, data: []u8) []align(page_size) u8 {
        std.debug.print("Writing {d} bytes @ {*}...\n", .{ data.len, self.cursor });

        const dest = self.cursor[0..data.len];
        std.mem.copy(u8, dest, data);
        // self.offset += data.len;

        const new = &self.global[data.len];
        const cursor = MapRequest.align_low(new);
        self.cursor = cursor;

        return @alignCast(dest);
    }

    pub fn mprotect(self: MapRequest, addr: []align(page_size) u8, prot: u32) void {
        _ = self;
        std.os.mprotect(addr, prot) catch |err| {
            std.debug.print("mprotect err >>> {!}\n", .{err});
        };
    }

    pub fn align_low(addr: *u8) [*]align(page_size) u8 {
        const int = @intFromPtr(addr);
        const ptr: [*]align(page_size) u8 = @ptrFromInt(int & ~(page_size - 1));

        return ptr;
    }

    pub fn close(self: *MapRequest) void {
        std.os.munmap(self.global);
        self.allocator.destroy(self);
    }
};
