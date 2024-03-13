const std = @import("std");

pub const QoiHeader = packed struct {
    width: u32,
    height: u32,
    channels: u8,
    colour_space: u8,

    pub const HeaderError = error{
        InvalidHeader,
        WrongFiletype,
    };

    const correct_magic = "qoif";
    pub const size = 14;

    pub fn from_bytes(bytes: []const u8) HeaderError!QoiHeader {
        if (bytes.len < @sizeOf(QoiHeader)) {
            return HeaderError.InvalidHeader;
        }
        if (!std.mem.eql(u8, bytes[0..correct_magic.len], correct_magic)) {
            return HeaderError.WrongFiletype;
        }
        const header_bytes = bytes[correct_magic.len..size];
        const width_offset = @offsetOf(QoiHeader, "width");
        const width = std.mem.readInt(u32, header_bytes[width_offset .. width_offset + @sizeOf(u32)], .Big);
        const height_offset = @offsetOf(QoiHeader, "width");
        const height = std.mem.readInt(u32, header_bytes[height_offset .. height_offset + @sizeOf(u32)], .Big);
        const channels: u8 = header_bytes[@offsetOf(QoiHeader, "channels")];
        const colour_space: u8 = header_bytes[@offsetOf(QoiHeader, "colour_space")];

        return .{
            .width = width,
            .height = height,
            .channels = channels,
            .colour_space = colour_space,
        };
    }
};

const Pixel = packed struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

const QOI_OP = enum(u8) {
    QOI_OP_RGB = 0b11111110,
    QOI_OP_RGBA = 0b11111111,
    QOI_OP_INDEX = 0b00000000,
    QOI_OP_DIFF = 0b01000000,
    QOI_OP_LUMA = 0b10000000,
    QOI_OP_RUN = 0b11000000,
};

pub const QoiImage = struct {
    header: QoiHeader,
    pixels: []const Pixel,

    pub const QoiError = error{
        Malformed,
        OutOfMemory,
    };

    pub fn from_bytes(alloc: std.mem.Allocator, bytes: []const u8) !QoiImage {
        var header = try QoiHeader.from_bytes(bytes);
        var pixels = try decode_pixels(alloc, header, bytes[QoiHeader.size..bytes.len]);

        return .{
            .header = header,
            .pixels = pixels,
        };
    }

    pub fn free(self: QoiImage, alloc: std.mem.Allocator) void {
        alloc.free(self.pixels);
    }

    fn decode_pixels(alloc: std.mem.Allocator, header: QoiHeader, bytes: []const u8) QoiError![]const Pixel {
        var pixels = alloc.alloc(Pixel, header.width * header.height) catch return QoiError.OutOfMemory;

        var pixel_i: u64 = 0;
        var i: u64 = 0;
        var prev_pixel: Pixel = .{ .r = 0, .g = 0, .b = 0, .a = 255 };
        while (i < bytes.len) {
            if (pixel_i >= pixels.len) {
                break;
            }

            const instruction = bytes[i];
            var pixel = prev_pixel;
            if (instruction == @intFromEnum(QOI_OP.QOI_OP_RGB)) {
                i += 1;
                const r: u8 = bytes[i];
                i += 1;
                const g: u8 = bytes[i];
                i += 1;
                const b: u8 = bytes[i];

                pixel = .{ .r = r, .g = g, .b = b, .a = prev_pixel.a };
            } else if (instruction == @intFromEnum(QOI_OP.QOI_OP_RGBA)) {
                i += 1;
                const r: u8 = bytes[i];
                i += 1;
                const g: u8 = bytes[i];
                i += 1;
                const b: u8 = bytes[i];
                i += 1;
                const a: u8 = bytes[i];

                pixel = .{ .r = r, .g = g, .b = b, .a = a };
            } else if (instruction >> 6 == @intFromEnum(QOI_OP.QOI_OP_DIFF) >> 6) {
                const r_diff: u2 = @truncate(instruction >> 4);
                const g_diff: u2 = @truncate(instruction >> 2);
                const b_diff: u2 = @truncate(instruction);
                pixel.r = calc_diff(pixel.r, r_diff);
                pixel.g = calc_diff(pixel.g, g_diff);
                pixel.b = calc_diff(pixel.b, b_diff);
            }
            prev_pixel = pixel;
            pixels[pixel_i] = pixel;

            pixel_i += 1;
            i += 1;
        }
        return pixels;
    }

    fn calc_diff(colour: u8, diff: u2) u8 {
        return switch (diff) {
            0 => colour -% 2,
            1 => colour -% 1,
            2 => colour,
            3 => colour +% 1,
        };
    }
};
