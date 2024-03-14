const std = @import("std");
const zigqoi = @import("zigqoi");

const Command = enum {
    Encode,
    Decode,
    Invalid,
};

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
        filepath = arg;
    }

    switch (command) {
        .Decode => try decode(alloc, filepath, enable_hex_print),
        .Encode => try encode(alloc),
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

fn encode(alloc: std.mem.Allocator) !void {
    _ = alloc;
    const header = zigqoi.QoiHeader.init(4, 4, 3, 0).to_bytes();
    std.debug.print("encoded header({} bytes): ", .{header.len});
    for (header) |byte| {
        std.debug.print("{x:0>2}", .{byte});
    }
    std.debug.print("\n", .{});
}
