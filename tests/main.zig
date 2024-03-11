const std = @import("std");
const zigqoi = @import("zigqoi");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len <= 1) {
        std.debug.print("No path given\n", .{});
        std.process.exit(1);
    }

    const filepath = args[1];

    const file = try std.fs.cwd().openFile(filepath, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var stream = buf_reader.reader();

    const metadata = try file.metadata();
    var buffer = try alloc.alloc(u8, metadata.size());
    const bytes_read = try stream.readAll(buffer);
    std.debug.print("read {} bytes\n", .{bytes_read});

    var header = try zigqoi.qoi_header.from_bytes(buffer);
    std.debug.print("header for '{s}':\n", .{filepath});
    std.debug.print("  magic: {s}\n", .{header.magic.str()});
    std.debug.print("  width: {}\n", .{header.width});
    std.debug.print("  height: {}\n", .{header.height});
    std.debug.print("  channels: {}\n", .{header.channels});
    std.debug.print("  colour_space: {}\n", .{header.colour_space});
}
