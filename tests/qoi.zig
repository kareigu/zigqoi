const std = @import("std");
const testing = std.testing;
const zigqoi = @import("zigqoi");

const alloc = std.testing.allocator;

const four_by_four = @embedFile("4x4.qoi");
const six_by_six = @embedFile("6x6.qoi");
const png_file = @embedFile("4x4.png");

test "read QoiHeader" {
    var header = try zigqoi.QoiHeader.from_bytes(four_by_four);
    try std.testing.expect(header.width == 4);
    try std.testing.expect(header.height == 4);
    try std.testing.expect(header.channels == 3);
    try std.testing.expect(header.colour_space == 0);

    try std.testing.expectError(zigqoi.QoiHeader.HeaderError.WrongFiletype, zigqoi.QoiHeader.from_bytes(png_file));
}

test "read QoiImage" {
    var image = try zigqoi.QoiImage.from_bytes(alloc, four_by_four);
    defer image.free(alloc);
    try std.testing.expect(image.pixels.len == image.header.width * image.header.height);
    try std.testing.expectError(zigqoi.QoiHeader.HeaderError.WrongFiletype, zigqoi.QoiImage.from_bytes(alloc, png_file));
}

test "read QoiImage OutOfMemory" {
    const fail_alloc = std.testing.failing_allocator;
    try std.testing.expectError(zigqoi.QoiImage.QoiError.OutOfMemory, zigqoi.QoiImage.from_bytes(fail_alloc, four_by_four));
}

test "validate QoiImage" {
    var image = try zigqoi.QoiImage.from_bytes(alloc, six_by_six);
    defer image.free(alloc);
    try std.testing.expect(image.pixels[8].r == 0xeb);
    try std.testing.expect(image.pixels[8].g == 0x00);
    try std.testing.expect(image.pixels[8].b == 0x14);
    try std.testing.expect(image.pixels[10].r == 0xed);
    try std.testing.expect(image.pixels[10].g == 0x01);
    try std.testing.expect(image.pixels[10].b == 0x13);
    try std.testing.expect(image.pixels[18].r == 0xb2);
    try std.testing.expect(image.pixels[18].g == 0x0a);
    try std.testing.expect(image.pixels[18].b == 0x57);
    try std.testing.expect(image.pixels[27].r == 0x7e);
    try std.testing.expect(image.pixels[27].g == 0x17);
    try std.testing.expect(image.pixels[27].b == 0x98);
}

test "encode QoiHeader" {
    const header = zigqoi.QoiHeader.init(4, 6, 3, 0).to_bytes();
    try std.testing.expect(std.mem.eql(u8, header[0..4], "qoif"));
    const width = std.mem.readIntBig(u32, header[4..8]);
    try std.testing.expect(width == 0x04);
    const height = std.mem.readIntBig(u32, header[8..12]);
    try std.testing.expect(height == 0x06);
    try std.testing.expect(header[12] == 0x03);
    try std.testing.expect(header[13] == 0x00);
}
