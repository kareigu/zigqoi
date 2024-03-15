const std = @import("std");
const zigqoi = @import("zigqoi");

const Command = enum {
    Encode,
    Decode,
    Test,
    Invalid,
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len <= 2) {
        std.debug.print("No path given\n", .{});
        std.process.exit(1);
    }

    var filepath: []u8 = undefined;
    var command = Command.Invalid;
    var enable_hex_print = false;
    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "--")) {
            if (std.mem.eql(u8, arg[2..arg.len], "hex")) {
                enable_hex_print = true;
            }
            continue;
        }
        if (std.mem.startsWith(u8, arg, "d")) {
            if (arg.len == 1 or std.mem.eql(u8, arg, "decode")) {
                command = .Decode;
                continue;
            }
        }
        if (std.mem.startsWith(u8, arg, "e")) {
            if (arg.len == 1 or std.mem.eql(u8, arg, "encode")) {
                command = .Encode;
                continue;
            }
        }
        if (std.mem.startsWith(u8, arg, "t")) {
            if (arg.len == 1 or std.mem.eql(u8, arg, "test")) {
                command = .Test;
                continue;
            }
        }
        filepath = arg;
    }

    switch (command) {
        .Decode => try decode(alloc, filepath, enable_hex_print),
        .Encode => try encode(alloc, filepath),
        .Test => try test_decode_encode(alloc, filepath),
        .Invalid => {
            std.debug.print("Select a command\n", .{});
            std.process.exit(1);
        },
    }
}

fn decode(alloc: std.mem.Allocator, filepath: []const u8, enable_hex_print: bool) !void {
    const file = try std.fs.cwd().openFile(filepath, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var stream = buf_reader.reader();

    const metadata = try file.metadata();
    var buffer = try alloc.alloc(u8, metadata.size());
    const bytes_read = try stream.readAll(buffer);
    std.debug.print("read {} bytes\n", .{bytes_read});

    var image = zigqoi.QoiImage.from_bytes(alloc, buffer) catch |e| {
        std.debug.print("ERROR: {s}\n", .{@errorName(e)});
        std.process.exit(1);
    };
    defer image.free(alloc);
    std.debug.print("header for '{s}':\n", .{filepath});
    std.debug.print("  width: {}\n", .{image.header.width});
    std.debug.print("  height: {}\n", .{image.header.height});
    std.debug.print("  channels: {}\n", .{image.header.channels});
    std.debug.print("  colour_space: {}\n", .{image.header.colour_space});

    std.debug.print("pixels:\n", .{});
    var x: u32 = 0;
    for (image.pixels) |pixel| {
        std.debug.print("\x1b[48;2;{};{};{}m", .{ pixel.r, pixel.g, pixel.b });
        if (enable_hex_print) {
            std.debug.print("{x:0>2}{x:0>2}{x:0>2} ", .{ pixel.r, pixel.g, pixel.b });
        } else {
            std.debug.print("  ", .{});
        }
        std.debug.print("\x1b[0m", .{});
        x += 1;
        if (x >= image.header.width) {
            std.debug.print("\n", .{});
            x = 0;
        }
    }
    std.debug.print("\n", .{});
}

fn encode(alloc: std.mem.Allocator, filepath: []const u8) !void {
    const header = zigqoi.QoiHeader.init(4, 4, 3, 0);
    const pixels = [4 * 4]zigqoi.Pixel{
        .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .{ .r = 0, .g = 255, .b = 255, .a = 255 },
        .{ .r = 255, .g = 0, .b = 255, .a = 255 },
        .{ .r = 255, .g = 0, .b = 255, .a = 255 },
        .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .{ .r = 0, .g = 255, .b = 255, .a = 255 },
        .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .{ .r = 255, .g = 255, .b = 0, .a = 255 },
        .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .{ .r = 255, .g = 0, .b = 255, .a = 255 },
        .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .{ .r = 254, .g = 255, .b = 255, .a = 255 },
        .{ .r = 255, .g = 0, .b = 0, .a = 255 },
        .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    };
    const image = zigqoi.QoiImage{ .header = header, .pixels = &pixels };
    const bytes = try image.to_bytes(alloc);
    std.debug.print("encoded ({} bytes): ", .{bytes.len});

    const file = try std.fs.cwd().createFile(filepath, .{});
    defer file.close();

    var buf_writer = std.io.bufferedWriter(file.writer());
    var stream = buf_writer.writer();
    for (bytes) |byte| {
        try stream.writeByte(byte);
        std.debug.print("{x:0>2}", .{byte});
    }
    try buf_writer.flush();
    std.debug.print("\n", .{});
}

fn test_decode_encode(alloc: std.mem.Allocator, filepath: []const u8) !void {
    const file = try std.fs.cwd().openFile(filepath, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var stream = buf_reader.reader();

    const metadata = try file.metadata();
    var buffer = try alloc.alloc(u8, metadata.size());
    const bytes_read = try stream.readAll(buffer);
    std.debug.print("read {} bytes\n", .{bytes_read});

    var image = zigqoi.QoiImage.from_bytes(alloc, buffer) catch |e| {
        std.debug.print("ERROR: {s}\n", .{@errorName(e)});
        std.process.exit(1);
    };
    defer image.free(alloc);
    std.debug.print("header for '{s}':\n", .{filepath});
    std.debug.print("  width: {}\n", .{image.header.width});
    std.debug.print("  height: {}\n", .{image.header.height});
    std.debug.print("  channels: {}\n", .{image.header.channels});
    std.debug.print("  colour_space: {}\n", .{image.header.colour_space});

    std.debug.print("pixels:\n", .{});
    {
        var x: u32 = 0;
        for (image.pixels) |pixel| {
            std.debug.print("\x1b[48;2;{};{};{}m", .{ pixel.r, pixel.g, pixel.b });
            std.debug.print("  ", .{});
            std.debug.print("\x1b[0m", .{});
            x += 1;
            if (x >= image.header.width) {
                std.debug.print("\n", .{});
                x = 0;
            }
        }
        std.debug.print("\n", .{});
    }

    const bytes = try image.to_bytes(alloc);
    std.debug.print("encoded ({} bytes): ", .{bytes.len});
    for (bytes) |byte| {
        std.debug.print("{x:0>2}", .{byte});
    }
    std.debug.print("\n", .{});

    var new_image = zigqoi.QoiImage.from_bytes(alloc, bytes) catch |e| {
        std.debug.print("ERROR: {s}\n", .{@errorName(e)});
        std.process.exit(1);
    };
    defer new_image.free(alloc);
    std.debug.print("header for '{s}':\n", .{filepath});
    std.debug.print("  width: {}\n", .{new_image.header.width});
    std.debug.print("  height: {}\n", .{new_image.header.height});
    std.debug.print("  channels: {}\n", .{new_image.header.channels});
    std.debug.print("  colour_space: {}\n", .{new_image.header.colour_space});

    std.debug.print("pixels:\n", .{});

    {
        var x: u32 = 0;
        for (new_image.pixels) |pixel| {
            std.debug.print("\x1b[48;2;{};{};{}m", .{ pixel.r, pixel.g, pixel.b });
            std.debug.print("  ", .{});
            std.debug.print("\x1b[0m", .{});
            x += 1;
            if (x >= new_image.header.width) {
                std.debug.print("\n", .{});
                x = 0;
            }
        }
        std.debug.print("\n", .{});
    }

    for (new_image.pixels, image.pixels) |new_pixel, old_pixel| {
        if (!std.meta.eql(new_pixel, old_pixel)) {
            std.debug.print("Different pixel found:\n", .{});
            std.debug.print("  should be r = {} g = {} b = {} a = {}\n", .{ new_pixel.r, new_pixel.g, new_pixel.b, new_pixel.a });
            std.debug.print("  found r = {} g = {} b = {} a = {}\n", .{ old_pixel.r, old_pixel.g, old_pixel.b, old_pixel.a });
        }
    }
}
