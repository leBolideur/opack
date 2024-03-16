const std = @import("std");
const OData = @import("odata.zig").OData;

fn sliceUntilZero(arr: [16]u8) []const u8 {
    for (arr, 0..) |byte, index| {
        if (byte == 0) {
            return arr[0..index];
        }
    }
    return arr[0..];
}

fn format_prot(prot: std.macho.vm_prot_t) [3]u8 {
    const PROT = std.macho.PROT;
    var buffer = [3]u8{ '-', '-', '-' };

    if ((prot & PROT.READ) != 0) {
        buffer[0] = 'R';
    }
    if ((prot & PROT.WRITE) != 0) {
        buffer[1] = 'W';
    }
    if ((prot & PROT.EXEC) != 0) {
        buffer[2] = 'X';
    }

    return buffer;
}

pub fn print_test(odata: *OData) void {
    for (odata.segment_cmds.items) |seg| {
        std.debug.print("{s:<18}fileoff: {d:<7}vmaddr: 0x0{x:<15}maxprot: {s:<8}initprot: {s}\n", .{
            sliceUntilZero(seg.segment_cmd.segname),
            seg.segment_cmd.fileoff,
            seg.segment_cmd.vmaddr,
            format_prot(seg.segment_cmd.maxprot),
            format_prot(seg.segment_cmd.initprot),
        });
        if (seg.sections) |sections| {
            for (sections.items) |sec| {
                std.debug.print("    secname: {s:>16}\n", .{sec.sectname});
            }
        }
    }
    std.debug.print("MAIN Entry: {x:>10}\n", .{odata.entrypoint_cmd.entryoff});
}
