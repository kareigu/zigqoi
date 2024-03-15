//!
//! zigqoi
//! library functions for encoding/decoding qoi formatted image data.
//!
const std = @import("std");

///
/// Header metadata of a qoi formatted image.
///
pub const QoiHeader = packed struct {
    /// Image width in pixels
    width: u32,
    /// Image height in pixels
    height: u32,
    /// Number of colour channels in the image
    /// 3 = RGB
    /// 4 = RGBA
    channels: u8,
    /// Colour space used in the image
    /// 0 = sRGB with linear alpa
    /// 1 = all channels linear
    colour_space: u8,

    pub const HeaderDecodingError = error{
        InvalidHeader,
        WrongFiletype,
    };

    const correct_magic = "qoif";

    /// Header size bytes
    pub const size = 14;

    pub fn init(width: u32, height: u32, channels: u8, colour_space: u8) QoiHeader {
        return .{
            .width = width,
            .height = height,
            .channels = channels,
            .colour_space = colour_space,
        };
    }

    ///
    /// Decode qoi image header data from a byte array
    ///
    pub fn from_bytes(bytes: []const u8) HeaderDecodingError!QoiHeader {
        if (bytes.len < @sizeOf(QoiHeader)) {
            return HeaderDecodingError.InvalidHeader;
        }
        if (!std.mem.eql(u8, bytes[0..correct_magic.len], correct_magic)) {
            return HeaderDecodingError.WrongFiletype;
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

    ///
    /// Encode QoiHeader into a byte array
    ///
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

///
/// A pixel containing colour data in the 8 bit RGBA format
///
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
    ///
    /// Check if pixel could be encoded as QOI_OP_DIFF
    /// Returns encoded pixels if possible
    ///
    pub fn diffable(self: @This(), previous: @TypeOf(self)) ?u6 {
        var diff: u6 = 0x00;

        const r_diff: i16 = @as(i16, self.r) - @as(i16, previous.r);
        if (r_diff > 1 or r_diff < -2)
            return null;
        diff |= @as(u6, add_bias(@as(i2, @truncate(r_diff)))) << 4;

        const g_diff: i16 = @as(i16, self.g) - @as(i16, previous.g);
        if (g_diff > 1 or g_diff < -2)
            return null;
        diff |= @as(u6, add_bias(@as(i2, @truncate(g_diff)))) << 2;

        const b_diff: i16 = @as(i16, self.b) - @as(i16, previous.b);
        if (b_diff > 1 or b_diff < -2)
            return null;
        diff |= @as(u6, add_bias(@as(i2, @truncate(b_diff)))) << 2;

        return diff;
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

///
/// Struct containing the header metadata
/// and an array of `Pixel`s of a qoi formatted image.
///
pub const QoiImage = struct {
    header: QoiHeader,
    pixels: []const Pixel,

    pub const QoiDecodingError = error{
        /// Decoded pixel data was malformed
        Malformed,
        OutOfMemory,
    };

    ///
    /// Decode an array of bytes into a QoiImage
    /// Input bytes need to be correctly encoded qoi data.
    ///
    pub fn from_bytes(alloc: std.mem.Allocator, bytes: []const u8) !QoiImage {
        var header = try QoiHeader.from_bytes(bytes);
        var pixels = try decode_pixels(alloc, header, bytes[QoiHeader.size..bytes.len]);

        return .{
            .header = header,
            .pixels = pixels,
        };
    }

    ///
    /// Encode a QoiImage into bytes according to the qoi specification.
    ///
    pub fn to_bytes(self: QoiImage, alloc: std.mem.Allocator) ![]const u8 {
        const header_bytes = self.header.to_bytes();
        var bytes = try self.encode_pixels(alloc);

        @memcpy(bytes[0..QoiHeader.size], &header_bytes);

        return bytes;
    }

    ///
    /// Frees the underlying array of pixels.
    ///
    pub fn free(self: QoiImage, alloc: std.mem.Allocator) void {
        alloc.free(self.pixels);
    }

    fn decode_pixels(alloc: std.mem.Allocator, header: QoiHeader, bytes: []const u8) QoiDecodingError![]const Pixel {
        var pixels = alloc.alloc(Pixel, header.width * header.height) catch return QoiDecodingError.OutOfMemory;

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
                Pixel.add_signed(&pixel.r, rm_bias(r_diff));
                Pixel.add_signed(&pixel.g, rm_bias(g_diff));
                Pixel.add_signed(&pixel.b, rm_bias(b_diff));
            } else if (instruction >> 6 == @intFromEnum(QOI_OP.QOI_OP_LUMA) >> 6) {
                const g_diff: i8 = rm_bias(@as(u6, @truncate(instruction)));
                Pixel.add_signed(&pixel.g, g_diff);
                i += 1;
                const rb_diff = bytes[i];
                const r_diff: i8 = g_diff + rm_bias(@as(u4, @truncate(rb_diff >> 4)));
                const b_diff: i8 = g_diff + rm_bias(@as(u4, @truncate(rb_diff)));
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
        const end_marker_length = 8;
        var bytes = try alloc.alloc(u8, offset + size + end_marker_length);

        var prev_pixel = Pixel{ .r = 0, .g = 0, .b = 0, .a = 255 };
        var pixel_index: [64]Pixel = .{};
        var i: u64 = offset;
        var pixel_i: u64 = 0;
        while (pixel_i < self.pixels.len) {
            const pixel = self.pixels[pixel_i];
            if (std.meta.eql(pixel, prev_pixel)) {
                var j: u64 = 1;
                while (j + pixel_i < self.pixels.len and std.meta.eql(self.pixels[pixel_i + j], prev_pixel)) {
                    j += 1;
                }
                const run_length: u6 = @truncate(j - 1);
                pixel_i += run_length;
                const byte = @intFromEnum(QOI_OP.QOI_OP_RUN) | run_length;
                bytes[i] = byte;
                i += 1;
            } else if (is_in_index(pixel_index, pixel)) {
                const byte = @intFromEnum(QOI_OP.QOI_OP_INDEX) | pixel.hash_index();
                bytes[i] = byte;
                i += 1;
            } else if (pixel.diffable(prev_pixel)) |diff| {
                const byte = @intFromEnum(QOI_OP.QOI_OP_DIFF) | diff;
                bytes[i] = byte;
                i += 1;
            } else {
                bytes[i] = @intFromEnum(QOI_OP.QOI_OP_RGB);
                i += 1;
                bytes[i] = pixel.r;
                i += 1;
                bytes[i] = pixel.g;
                i += 1;
                bytes[i] = pixel.b;
                i += 1;
            }
            pixel_index[pixel.hash_index()] = pixel;
            prev_pixel = pixel;
            pixel_i += 1;
        }

        var shrinked_bytes = try alloc.alloc(u8, i + end_marker_length);
        @memcpy(shrinked_bytes[0..i], bytes[0..i]);
        alloc.free(bytes);

        for (shrinked_bytes.len - 8..shrinked_bytes.len - 1) |j| {
            shrinked_bytes[j] = 0x00;
        }
        shrinked_bytes[shrinked_bytes.len - 1] = 0x01;
        return shrinked_bytes;
    }

    fn is_in_index(pixel_index: [64]Pixel, pixel: Pixel) bool {
        if (std.meta.eql(pixel_index[pixel.hash_index()], pixel))
            return true;

        return false;
    }
};

fn bias_amount(comptime T: type) i8 {
    return std.math.maxInt(T) + 1;
}

fn bias_output_type(comptime T: type) type {
    return switch (T) {
        u2 => i2,
        u4 => i4,
        u6 => i6,
        i2 => u2,
        i4 => u4,
        i6 => u6,
        else => @compileError("Unsupported type"),
    };
}

fn add_bias(n: anytype) bias_output_type(@TypeOf(n)) {
    return @truncate(@as(u16, @intCast(@as(i16, n) + 2)));
}

fn rm_bias(n: anytype) bias_output_type(@TypeOf(n)) {
    return @intCast(@as(i8, n) - bias_amount(bias_output_type(@TypeOf(n))));
}
