const std = @import("std");
const testing = std.testing;
const zigqoi = @import("zigqoi");

test "read header functionality" {
    const test_file = @embedFile("4x4.qoi");
    var header = try zigqoi.qoi_header.from_bytes(test_file);
    try std.testing.expect(std.mem.eql(u8, &header.magic.str(), zigqoi.qoi_header.magic_string.valid_str));
    try std.testing.expect(header.width == 4);
    try std.testing.expect(header.height == 4);
    try std.testing.expect(header.channels == 3);
    try std.testing.expect(header.colour_space == 0);

    const png_file = @embedFile("4x4.png");
    try std.testing.expectError(zigqoi.qoi_header.header_error.WrongFiletype, zigqoi.qoi_header.from_bytes(png_file));
}
