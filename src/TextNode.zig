const std = @import("std");
const LeafNode = @import("LeafNode.zig").LeafNode;
const Node = @import("Node.zig").Node;

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
        try writer.print("{s}, ", .{self.text});
        try writer.print("{s}", .{@tagName(self.textType)});
        if (self.url.len > 0) {
            try writer.print(", {s})", .{self.url});
        } else {
            try writer.writeAll(")");
        }
    }

    pub fn toHtml(
        self: TextNode,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        var node = switch (self.textType) {
            .text => try LeafNode.init(allocator, "", self.text, false),
            .bold => try LeafNode.init(allocator, "b", self.text, false),
            .italic => try LeafNode.init(allocator, "i", self.text, false),
            .code => try LeafNode.init(allocator, "code", self.text, false),
            .link => linkBlk: {
                var tmp = try LeafNode.init(allocator, "a", self.text, false);
                try tmp.props.put("href", self.url);
                break :linkBlk tmp;
            },
            .image => imgBlk: {
                var tmp = try LeafNode.init(allocator, "img", "", true);
                try tmp.props.put("src", self.url);
                try tmp.props.put("alt", self.text);
                break :imgBlk tmp;
            },
            // else => @panic("Not implemented"),
        };
        defer node.deinit();
        const result = try node.toHtml(allocator);
        return result;
    }
};

test "text node" {
    const gpa = std.testing.allocator;
    const node = TextNode{
        .text = "just some text",
        .textType = TextType.text,
        .url = "",
    };

    const result = try node.toHtml(gpa);
    defer gpa.free(result);
    try std.testing.expectEqualStrings("just some text", result);
}

test "bold node" {
    const gpa = std.testing.allocator;
    const node = TextNode{
        .text = "just some bold text",
        .textType = TextType.bold,
        .url = "",
    };

    const result = try node.toHtml(gpa);
    defer gpa.free(result);
    try std.testing.expectEqualStrings("<b>just some bold text</b>", result);
}

test "italic node" {
    const gpa = std.testing.allocator;
    const node = TextNode{
        .text = "just some italic text",
        .textType = TextType.italic,
        .url = "",
    };

    const result = try node.toHtml(gpa);
    defer gpa.free(result);
    try std.testing.expectEqualStrings("<i>just some italic text</i>", result);
}

test "code node" {
    const gpa = std.testing.allocator;
    const node = TextNode{
        .text = "just some code text",
        .textType = TextType.code,
        .url = "",
    };

    const result = try node.toHtml(gpa);
    defer gpa.free(result);
    try std.testing.expectEqualStrings("<code>just some code text</code>", result);
}

test "link node" {
    const gpa = std.testing.allocator;
    const node = TextNode{
        .text = "click me",
        .textType = TextType.link,
        .url = "https://crimsonhexagon.us",
    };

    const result = try node.toHtml(gpa);
    defer gpa.free(result);
    try std.testing.expectEqualStrings("<a href=\"https://crimsonhexagon.us\">click me</a>", result);
}

test "image node" {
    const gpa = std.testing.allocator;
    const node = TextNode{
        .text = "alternate text",
        .textType = TextType.image,
        .url = "https://crimsonhexagon.us/image.png",
    };

    const result = try node.toHtml(gpa);
    defer gpa.free(result);
    try std.testing.expectStringStartsWith(result, "<img ");
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "alt=\"alternate text\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "src=\"https://crimsonhexagon.us/image.png\""));
    try std.testing.expectStringEndsWith(result, ">");
}

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
