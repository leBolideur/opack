const std = @import("std");

const MachOFile = @import("parser.zig").MachOFile;
const OData = @import("odata.zig").OData;
const printer = @import("printer.zig");

const GPAConfig = .{ .verbose_log = false };

pub const OPacker = struct {
    // odata: *OData,
    // gpa_alloc: *std.mem.Allocator,
    // gpa: std.heap.GeneralPurposeAllocator(GPAConfig),

    pub fn init(args: *std.process.ArgIteratorPosix) !void {
        var gpa = std.heap.GeneralPurposeAllocator(GPAConfig){};
        defer _ = gpa.deinit();

        var allocator = gpa.allocator();

        var odata_ptr = try OData.init(&allocator);
        defer odata_ptr.close();

        const ofile = try MachOFile.load(args, odata_ptr);
        defer ofile.close();

        const stats = try ofile.file.stat();

        var raw_ptr = try allocator.alloc(u8, stats.size);
        defer allocator.free(raw_ptr);

        try ofile.dump_all_raw(raw_ptr);
        std.debug.print("\nWhere is raw_ptr: {*}\n", .{(raw_ptr.ptr)});

        try ofile.parse();

        printer.print_test(odata_ptr);
        const text_lcmd = odata_ptr.get_textseg_cmd();
        if (text_lcmd == null) {
            std.debug.print("no __TEXT segment load cmd!\n", .{});
            return;
        }

        const sect = odata_ptr.get_text_sect();
        if (sect == null) {
            std.debug.print("no __text section!\n", .{});
            return;
        }

        std.debug.print("sect addr >> {x}\n", .{(sect.?.addr)});
        std.debug.print("sect offset >> {d}\traw size: {d}\n", .{ sect.?.offset, stats.size });
        std.debug.print("sect size >> {x}\n", .{(sect.?.size)});

        // const fileoff = text_lcmd.?.fileoff;
        // const size = text_lcmd.?.filesize;
        const fileoff = sect.?.offset;
        const size = sect.?.size;
        const sect_data = raw_ptr[fileoff..(fileoff + size)];
        std.debug.print("sect_data len : {d}\n", .{sect_data.len});

        {
            // var seg_data = try allocator.alloc(u8, text_lcmd.?.filesize);
            // defer allocator.free(seg_data);

            // try ofile.pick(text_lcmd.?.fileoff, text_lcmd.?.filesize, &seg_data);

            // Créer un fichier temporaire
            std.debug.print("\nDisassembling {s}...\n", .{ofile.filepath});
            var tmp_file = try std.fs.cwd().createFile(".bin", .{ .truncate = true });
            defer tmp_file.close();

            try tmp_file.writeAll(sect_data);

            const size_u64 = comptime @sizeOf(u64);
            var buf: [size_u64]u8 = undefined;
            const str = try std.fmt.bufPrint(buf[0..], "{}", .{odata_ptr.entrypoint_cmd.entryoff});
            // const argv = [_][]const u8{ "objdump", "-d", ".bin" };
            const argv = [_][]const u8{ "radare2", "-b", "64", "-m", str, "-qc", "\"pd 10\"", ".bin" };
            var proc = try std.ChildProcess.exec(.{
                .allocator = allocator,
                .argv = &argv,
            });

            std.debug.print("{s}\n", .{proc.stdout});
            std.debug.print("Err: {s}", .{proc.stderr});

            // on success, we own the output streams
            defer allocator.free(proc.stdout);
            defer allocator.free(proc.stderr);
        }

        std.debug.print("\nExecuting...\n\n", .{});

        std.debug.print(" sect_data @ {*:<15}\n", .{(sect_data)});

        const page_size: usize = comptime 0x4000;
        // std.debug.print("sys page_size: {d} (0x{0x})\n", .{page_size});

        // !!!!!! Verifier le calcul !!!!!!!
        const ptr_to_int = @intFromPtr(sect_data.ptr);
        var region: usize = ptr_to_int & ~(page_size - 1);
        var region_ptr: [*]align(page_size) u8 = @ptrFromInt(region);
        var region_slice = region_ptr[0..page_size];

        std.debug.print("region_ptr @ {*:<15}\n", .{region_ptr});
        std.debug.print("region_len @ {d:<15}\n", .{region_slice.len});

        try pause();

        const macho = std.macho;
        const prot = macho.PROT.READ | macho.PROT.WRITE | macho.PROT.EXEC;
        std.os.mprotect(region_slice, prot) catch |err| {
            std.debug.print("mprotect err >>> {!}\n", .{err});
        };

        try pause();

        std.debug.print("\nJumping @ 0x{*}...\n", .{sect_data});
        // const jmp: *const fn () void = @ptrCast(seg_data);
        // jmp();

        std.debug.print("\nSo far, so good...\n", .{});

        // return OPacker{
        //     .odata = odata_ptr,
        //     // .gpa_alloc = &allocator,
        //     // .gpa = gpa,
        // };
    }

    pub fn close(self: OPacker) void {
        _ = self;
        // self.odata.close();
        // _ = self.gpa.deinit();
    }
};

fn pause() !void {
    var input: [1]u8 = undefined;
    const stdin = std.io.getStdIn().reader();
    _ = try stdin.readUntilDelimiter(&input, '\n');
}
