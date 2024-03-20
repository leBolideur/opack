const std = @import("std");
const OData = @import("odata.zig").OData;

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

pub fn print_debug(odata: *OData) void {
    for (odata.load_cmds.items) |seg| {
        std.debug.print("{s:<15}fileoff: {x:<7}filesize: {d:<7}vmemrange: {x:0<9}..{x:<12}vmsize: {x:<12}maxprot: {s:<7}initprot: {s}\n", .{
            seg.segname,
            seg.segment_cmd.fileoff,
            seg.segment_cmd.filesize,
            seg.segment_cmd.vmaddr,
            seg.vmem_size(),
            seg.segment_cmd.vmsize,
            format_prot(seg.segment_cmd.maxprot),
            format_prot(seg.segment_cmd.initprot),
        });
        if (seg.sections) |sections| {
            for (sections.items) |sec| {
                std.debug.print("    secname: {s:<24}addr: {x}\n", .{ sec.sectname, sec.addr });
            }
        }
    }
    std.debug.print("MAIN Entry: {x:>10}\n", .{odata.entrypoint_cmd.entryoff});
}
