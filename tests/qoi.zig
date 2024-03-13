const std = @import("std");
const testing = std.testing;
const zigqoi = @import("zigqoi");

const alloc = std.testing.allocator;

const four_by_four = @embedFile("4x4.qoi");
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
