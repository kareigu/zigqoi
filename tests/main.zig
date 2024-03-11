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

    var image = zigqoi.qoi_image.from_bytes(alloc, buffer) catch |e| {
        std.debug.print("ERROR: {s}\n", .{@errorName(e)});
        std.process.exit(1);
    };
    defer image.free(alloc);
    std.debug.print("header for '{s}':\n", .{filepath});
    std.debug.print("  magic: {s}\n", .{image.header.magic.str()});
    std.debug.print("  width: {}\n", .{image.header.width});
    std.debug.print("  height: {}\n", .{image.header.height});
    std.debug.print("  channels: {}\n", .{image.header.channels});
    std.debug.print("  colour_space: {}\n", .{image.header.colour_space});

    std.debug.print("data:\n", .{});
    var x: u32 = 0;
    for (image.pixels) |pixel| {
        std.debug.print("\x1b[48;2;{};{};{}m", .{ pixel.r, pixel.g, pixel.b });
        std.debug.print("{x:0^2}{x:0^2}{x:0^2} ", .{ pixel.r, pixel.g, pixel.b });
        std.debug.print("\x1b[0m", .{});
        x += 1;
        if (x >= image.header.width) {
            std.debug.print("\n", .{});
            x = 0;
        }
    }
    std.debug.print("\n", .{});
}
