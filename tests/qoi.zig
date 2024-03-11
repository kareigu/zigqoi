const std = @import("std");
const testing = std.testing;
const zigqoi = @import("zigqoi");

const alloc = std.testing.allocator;

const test_file = @embedFile("4x4.qoi");
const png_file = @embedFile("4x4.png");

test "read qoi_header" {
    var header = try zigqoi.QoiHeader.from_bytes(test_file);
    try std.testing.expect(std.mem.eql(u8, &header.magic.str(), zigqoi.QoiHeader.magic_string.valid_str));
    try std.testing.expect(header.width == 4);
    try std.testing.expect(header.height == 4);
    try std.testing.expect(header.channels == 3);
    try std.testing.expect(header.colour_space == 0);

    try std.testing.expectError(zigqoi.QoiHeader.header_error.WrongFiletype, zigqoi.QoiHeader.from_bytes(png_file));
}

test "read qoi_image" {
    var image = try zigqoi.QoiImage.from_bytes(alloc, test_file);
    defer image.free(alloc);
    try std.testing.expect(image.pixels.len == image.header.width * image.header.height);
    try std.testing.expectError(zigqoi.QoiHeader.header_error.WrongFiletype, zigqoi.QoiImage.from_bytes(alloc, png_file));
}
