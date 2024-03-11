const std = @import("std");

pub const QoiHeader = packed struct {
    magic: magic_string,
    width: u32,
    height: u32,
    channels: u8,
    colour_space: u8,

    pub const magic_string = packed struct {
        m: u8,
        a: u8,
        g: u8,
        i: u8,

        pub fn str(self: magic_string) [4]u8 {
            return .{ self.m, self.a, self.g, self.i };
        }

        pub fn from_bytes(bytes: []const u8) header_error!magic_string {
            const m: u8 = bytes[@offsetOf(magic_string, "m")];
            if (m != valid_str[0]) {
                return error.WrongFiletype;
            }
            const a: u8 = bytes[@offsetOf(magic_string, "a")];
            if (a != valid_str[1]) {
                return error.WrongFiletype;
            }
            const g: u8 = bytes[@offsetOf(magic_string, "g")];
            if (g != valid_str[2]) {
                return error.WrongFiletype;
            }
            const i: u8 = bytes[@offsetOf(magic_string, "i")];
            if (i != valid_str[3]) {
                return header_error.WrongFiletype;
            }

            return .{
                .m = m,
                .a = a,
                .g = g,
                .i = i,
            };
        }

        pub const valid_str = "qoif";
    };

    pub const header_error = error{
        InvalidHeader,
        WrongFiletype,
    };

    pub fn from_bytes(bytes: []const u8) header_error!QoiHeader {
        if (bytes.len < @sizeOf(QoiHeader)) {
            return header_error.InvalidHeader;
        }
        const header_bytes = bytes[0 .. @bitSizeOf(QoiHeader) / 8];
        const magic = try magic_string.from_bytes(header_bytes[0 .. @bitSizeOf(QoiHeader.magic_string) / 8]);
        const width = std.mem.readVarInt(u32, header_bytes[@offsetOf(QoiHeader, "width") .. @offsetOf(QoiHeader, "width") + @sizeOf(u32)], std.builtin.Endian.Big);
        const height = std.mem.readVarInt(u32, header_bytes[@offsetOf(QoiHeader, "height") .. @offsetOf(QoiHeader, "height") + @sizeOf(u32)], std.builtin.Endian.Big);
        const channels: u8 = header_bytes[@offsetOf(QoiHeader, "channels")];
        const colour_space: u8 = header_bytes[@offsetOf(QoiHeader, "colour_space")];

        return .{
            .magic = magic,
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

    pub const qoi_error = error{
        Malformed,
        OutOfMemory,
    };

    pub fn from_bytes(alloc: std.mem.Allocator, bytes: []const u8) !QoiImage {
        var header = try QoiHeader.from_bytes(bytes);
        var pixels = try decode_pixels(alloc, header, bytes[@bitSizeOf(QoiHeader) / 8 .. bytes.len]);

        return .{
            .header = header,
            .pixels = pixels,
        };
    }

    pub fn free(self: QoiImage, alloc: std.mem.Allocator) void {
        alloc.free(self.pixels);
    }

    fn decode_pixels(alloc: std.mem.Allocator, header: QoiHeader, bytes: []const u8) qoi_error![]const Pixel {
        var pixels = alloc.alloc(Pixel, header.width * header.height) catch return qoi_error.OutOfMemory;
        var x: u32 = 0;
        var y: u32 = 0;

        var i: u64 = 0;
        var prev_pixel: Pixel = .{ .r = 0, .g = 0, .b = 0, .a = 255 };
        while (i < bytes.len) {
            const instruction = bytes[i];
            if (instruction == @intFromEnum(QOI_OP.QOI_OP_RGB)) {
                i += 1;
                const r: u8 = bytes[i];
                i += 1;
                const g: u8 = bytes[i];
                i += 1;
                const b: u8 = bytes[i];

                const p = .{ .r = r, .g = g, .b = b, .a = prev_pixel.a };
                prev_pixel = p;
                pixels[x * y] = p;
            } else if (instruction == @intFromEnum(QOI_OP.QOI_OP_RGBA)) {
                i += 1;
                const r: u8 = bytes[i];
                i += 1;
                const g: u8 = bytes[i];
                i += 1;
                const b: u8 = bytes[i];
                i += 1;
                const a: u8 = bytes[i];

                const pixel = .{ .r = r, .g = g, .b = b, .a = a };
                prev_pixel = pixel;
                pixels[x * y] = pixel;
            }

            x += 1;
            if (x >= 4) {
                y += 1;
                x = 0;
            }
            i += 1;
        }
        return pixels;
    }
};
