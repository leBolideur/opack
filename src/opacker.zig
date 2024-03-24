const std = @import("std");

// const MachOFile = @import("parser.zig").MachOFile;
// const OData = @import("odata.zig").OData;
// const printer = @import("printer.zig");

// const omap_import = @import("omap.zig");
// const OMap = omap_import.OMap;
// const MapRequest = omap_import.MapRequest;

// const GPAConfig = .{ .verbose_log = false };

const MemoryError = error{MmapFailed};
const PackerError = anyerror || MemoryError;

fn pause() !void {
    var input: [1]u8 = undefined;
    const stdin = std.io.getStdIn().reader();
    _ = try stdin.readUntilDelimiter(&input, '\n');
}

// pub const OPacker = struct {
//     pub fn pack(self: OPacker) void {
//         const int: usize = @intFromPtr(self.omap.entry_text);
//         const add: usize = int + self.omap.entry_point;
//         const to_ptr: [*]u8 = @ptrFromInt(add);
//         std.debug.print("\nentryoff: 0x{x}\nentry_text: {*}\nint: {x}\nadd: {x}\nto_ptr @ {*}...\n", .{
//             self.odata.entrypoint_cmd.entryoff,
//             self.omap.entry_text,
//             int,
//             add,
//             to_ptr,
//         });

//         // try pause();
//         std.debug.print("\nJumping @ {*}...\n", .{to_ptr});

//         const jump: *const fn () void = @alignCast(@ptrCast(to_ptr));
//         jump();

//         std.debug.print("\nSo far, so good...\n", .{});
//     }
// };
