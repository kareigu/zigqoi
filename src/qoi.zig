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

    pub fn init(width: u32, height: u32, channels: u8, colour_space: u8) QoiHeader {
        return .{
            .width = width,
            .height = height,
            .channels = channels,
            .colour_space = colour_space,
        };
    }

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

    pub fn to_bytes(self: QoiHeader) [size]u8 {
        var header: [size]u8 = std.mem.zeroes([size]u8);
        @memcpy(header[0..correct_magic.len], correct_magic);
        const width_offset = correct_magic.len + @offsetOf(QoiHeader, "width");
        std.mem.writeIntSliceBig(u32, header[width_offset .. width_offset + @sizeOf(u32)], self.width);
        const height_offset = correct_magic.len + @offsetOf(QoiHeader, "height");
        std.mem.writeIntSliceBig(u32, header[height_offset .. height_offset + @sizeOf(u32)], self.height);
        header[@offsetOf(QoiHeader, "channels") + correct_magic.len] = self.channels;
        header[@offsetOf(QoiHeader, "colour_space") + correct_magic.len] = self.colour_space;
        return header;
    }
};

pub const Pixel = packed struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub fn hash_index(self: Pixel) u6 {
        return @truncate((self.r *% 3 +% self.g *% 5 +% self.b *% 7 +% self.a *% 11) % 64);
    }
    pub fn add_signed(val: *u8, diff: i8) void {
        val.* +%= @bitCast(diff);
    }
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

    pub fn to_bytes(self: QoiImage, alloc: std.mem.Allocator) ![]const u8 {
        const header_bytes = self.header.to_bytes();
        var bytes = try self.encode_pixels(alloc);

        @memcpy(bytes[0..QoiHeader.size], &header_bytes);

        return bytes;
    }

    pub fn free(self: QoiImage, alloc: std.mem.Allocator) void {
        alloc.free(self.pixels);
    }

    fn decode_pixels(alloc: std.mem.Allocator, header: QoiHeader, bytes: []const u8) QoiError![]const Pixel {
        var pixels = alloc.alloc(Pixel, header.width * header.height) catch return QoiError.OutOfMemory;

        var pixel_i: u64 = 0;
        var i: u64 = 0;
        var prev_pixel: Pixel = .{ .r = 0, .g = 0, .b = 0, .a = 255 };
        var pixel_index: [64]Pixel = .{};
        while (i < bytes.len and pixel_i < pixels.len) {
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
            } else if (instruction >> 6 == @intFromEnum(QOI_OP.QOI_OP_INDEX) >> 6) {
                const index: u6 = @truncate(instruction);
                pixel = pixel_index[index];
            } else if (instruction >> 6 == @intFromEnum(QOI_OP.QOI_OP_DIFF) >> 6) {
                const r_diff: u2 = @truncate(instruction >> 4);
                const g_diff: u2 = @truncate(instruction >> 2);
                const b_diff: u2 = @truncate(instruction);
                Pixel.add_signed(&pixel.r, rm_bias_u2(r_diff));
                Pixel.add_signed(&pixel.g, rm_bias_u2(g_diff));
                Pixel.add_signed(&pixel.b, rm_bias_u2(b_diff));
            } else if (instruction >> 6 == @intFromEnum(QOI_OP.QOI_OP_LUMA) >> 6) {
                const g_diff: i8 = rm_bias_u6(@truncate(instruction));
                Pixel.add_signed(&pixel.g, g_diff);
                i += 1;
                const rb_diff = bytes[i];
                const r_diff: i8 = g_diff + rm_bias_u4(@truncate(rb_diff >> 4));
                const b_diff: i8 = g_diff + rm_bias_u4(@truncate(rb_diff));
                Pixel.add_signed(&pixel.r, r_diff);
                Pixel.add_signed(&pixel.b, b_diff);
            } else if (instruction >> 6 == @intFromEnum(QOI_OP.QOI_OP_RUN) >> 6) {
                const run_length: u6 = @truncate(instruction);
                for (0..run_length + 1) |_| {
                    pixels[pixel_i] = prev_pixel;
                    pixel_i += 1;
                }
                i += 1;
                continue;
            }
            prev_pixel = pixel;
            pixel_index[pixel.hash_index()] = pixel;
            pixels[pixel_i] = pixel;

            pixel_i += 1;
            i += 1;
        }
        return pixels;
    }

    fn encode_pixels(self: QoiImage, alloc: std.mem.Allocator) ![]u8 {
        const offset = QoiHeader.size;
        const size = self.pixels.len * 4;
        var bytes = try alloc.alloc(u8, offset + size + 8);

        var i: u64 = offset;
        for (self.pixels) |pixel| {
            bytes[i] = @intFromEnum(QOI_OP.QOI_OP_RGB);
            i += 1;
            bytes[i] = pixel.r;
            i += 1;
            bytes[i] = pixel.g;
            i += 1;
            bytes[i] = pixel.b;
            i += 1;
        }

        for (bytes.len - 8..bytes.len - 1) |j| {
            bytes[j] = 0x00;
        }
        bytes[bytes.len - 1] = 0x01;
        return bytes;
    }

    fn bias_amount(comptime T: type) i8 {
        return std.math.maxInt(T) + 1;
    }

    fn rm_bias_u2(n: u2) i2 {
        return @intCast(@as(i8, n) - bias_amount(i2));
    }

    fn rm_bias_u4(n: u4) i4 {
        return @intCast(@as(i8, n) - bias_amount(i4));
    }

    fn rm_bias_u6(n: u6) i6 {
        return @intCast(@as(i8, n) - bias_amount(i6));
    }
};
