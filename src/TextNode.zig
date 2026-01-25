const std = @import("std");

pub const TextType = enum { text, bold, italic, code, link, image };

pub const TextNode = struct {
    text: []const u8,
    textType: TextType,
    url: []const u8,

    pub fn format(
        self: TextNode,
        writer: anytype,
    ) !void {
        try writer.writeAll("TextNode(");
        _ = try writer.print("{s}, ", .{self.text});
        _ = try writer.print("{s}", .{@tagName(self.textType)});
        if (self.url.len > 0) {
            _ = try writer.print(", {s})", .{self.url});
        } else {
            try writer.writeAll(")");
        }
    }
};

test "test equality" {
    const node = TextNode{
        .text = "This is a text node",
        .textType = TextType.bold,
        .url = "",
    };
    const node2 = TextNode{
        .text = "This is a text node",
        .textType = TextType.bold,
        .url = "",
    };
    try std.testing.expectEqual(node, node2);
}

test "test non-equality" {
    const node = TextNode{
        .text = "This is a text node",
        .textType = TextType.bold,
        .url = "",
    };
    const node2 = TextNode{
        .text = "This is a text node",
        .textType = TextType.bold,
        .url = "https://url.url",
    };
    try std.testing.expect(!std.meta.eql(node, node2));
}
