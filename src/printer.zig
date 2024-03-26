const std = @import("std");
const macho = std.macho;

const OData = @import("odata.zig").OData;

pub fn pause() !void {
    var input: [1]u8 = undefined;
    const stdin = std.io.getStdIn().reader();
    _ = try stdin.readUntilDelimiter(&input, '\n');
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

pub fn segment_cmds(odata: *OData) void {
    for (odata.load_cmds.items) |seg| {
        std.debug.print("{s:<15}fileoff: {x:<7}filesize: {d:<7}vmaddr: {x:<12}vmsize: {x:<12}maxprot: {s:<7}initprot: {s}\n", .{
            seg.segment_cmd.segName(),
            seg.segment_cmd.fileoff,
            seg.segment_cmd.filesize,
            seg.segment_cmd.vmaddr,
            seg.segment_cmd.vmsize,
            format_prot(seg.segment_cmd.maxprot),
            format_prot(seg.segment_cmd.initprot),
        });
        for (seg.sections.items) |sec| {
            std.debug.print("  {s:<20}addr: {x}\n", .{ sec.sectName(), sec.addr });
        }
        std.debug.print("\n", .{});
    }
}

pub fn symtab(odata: *OData) void {
    std.debug.print("Symtab:\n", .{});
    for (odata.symtab_entries.items) |nlist| {
        // if (nlist.sect()) {
        // std.debug.print("nlist value: 0x{x}\n", .{nlist.n_value});
        const seg = odata.segment_at(nlist.n_value);
        if (seg != null)
            std.debug.print(">> @ 0x{x}\tin {s}\n", .{ nlist.n_value, seg.?.segname });
        // }
    }
}
