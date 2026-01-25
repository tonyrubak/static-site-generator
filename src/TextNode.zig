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

    fn peek(
        text: []const u8,
        index: usize,
        c: u8,
    ) bool {
        return index + 1 < text.len and text[index + 1] == c;
    }

    fn emit(
        allocator: std.mem.Allocator,
        list: *std.ArrayList(TextNode),
        text: []const u8,
        kind: TextType,
        url: ?[]const u8,
    ) !void {
        if (text.len > 0) {
            try list.append(allocator, .{
                .text = text,
                .textType = kind,
                .url = url orelse "",
            });
        }
    }

    pub fn splitNode(
        self: TextNode,
        allocator: std.mem.Allocator,
    ) ![]TextNode {
        var list = std.ArrayList(TextNode).empty;
        errdefer list.deinit(allocator);

        if (self.textType != .text) {
            const tmp = TextNode{ .text = self.text, .textType = self.textType, .url = self.url };
            try list.append(allocator, tmp);
            return list.toOwnedSlice(allocator);
        }

        var index: usize = 0;
        var current: usize = 0;
        var in_tag: ?TextType = null;

        while (index < self.text.len) {
            switch (self.text[index]) {
                '*' => {
                    const is_double_star = peek(self.text, index, '*');
                    if (is_double_star and in_tag == null) {
                        in_tag = .bold;
                        try TextNode.emit(allocator, &list, self.text[current..index], .text, null);
                        index += 2;
                        current = index;
                    } else if (is_double_star and in_tag == .bold) {
                        in_tag = null;
                        try TextNode.emit(allocator, &list, self.text[current..index], .bold, null);
                        index += 2;
                        current = index;
                    } else if (is_double_star) {
                        return error.InvalidMarkdown;
                    } else {
                        index += 1;
                    }
                },
                '_' => {
                    if (in_tag == null) {
                        in_tag = .italic;
                        try TextNode.emit(allocator, &list, self.text[current..index], .text, null);
                        index += 1;
                        current = index;
                    } else if (in_tag == .italic) {
                        in_tag = null;
                        try TextNode.emit(allocator, &list, self.text[current..index], .italic, null);
                        index += 1;
                        current = index;
                    } else {
                        return error.InvalidMarkdown;
                    }
                },
                '`' => {
                    if (in_tag == null) {
                        in_tag = .code;
                        try TextNode.emit(allocator, &list, self.text[current..index], .text, null);
                        index += 1;
                        current = index;
                    } else if (in_tag == .code) {
                        in_tag = null;
                        try TextNode.emit(allocator, &list, self.text[current..index], .code, null);
                        index += 1;
                        current = index;
                    } else {
                        return error.InvalidMarkdown;
                    }
                },
                '[' => {
                    if (in_tag != null) return error.InvalidMarkdown;

                    try TextNode.emit(allocator, &list, self.text[current..index], .text, null);
                    index += 1;
                    current = index;
                    index += std.mem.indexOf(u8, self.text[current..], "]") orelse return error.InvalidMarkdown;
                    const value = switch (peek(self.text, index, '(')) {
                        true => self.text[current..index],
                        false => return error.InvalidMarkdown,
                    };
                    index += 2;
                    current = index;
                    index += std.mem.indexOf(u8, self.text[current..], ")") orelse return error.InvalidMarkdown;
                    const url = self.text[current..index];
                    try emit(allocator, &list, value, .link, url);
                    index += 1;
                    current = index;
                },
                '!' => {
                    if (!peek(self.text, index, '[')) {
                        index += 1;
                        continue;
                    }

                    if (in_tag != null) return error.InvalidMarkdown;

                    try TextNode.emit(allocator, &list, self.text[current..index], .text, null);
                    index += 2;
                    current = index;
                    index += std.mem.indexOf(u8, self.text[current..], "]") orelse return error.InvalidMarkdown;
                    const value = switch (peek(self.text, index, '(')) {
                        true => self.text[current..index],
                        false => return error.InvalidMarkdown,
                    };
                    index += 2;
                    current = index;
                    index += std.mem.indexOf(u8, self.text[current..], ")") orelse return error.InvalidMarkdown;
                    const url = self.text[current..index];
                    try emit(allocator, &list, value, .image, url);
                    index += 1;
                    current = index;
                },
                else => index += 1,
            }
        }

        if (in_tag != null) {
            return error.InvalidMarkdown;
        }

        if (current < self.text.len - 1) {
            try TextNode.emit(allocator, &list, self.text[current..], .text, null);
        }

        return list.toOwnedSlice(allocator);
    }
};

test "tag ends at end of line" {
    const gpa = std.testing.allocator;
    const node = TextNode{
        .text = "just some **bold text**",
        .textType = TextType.text,
        .url = "",
    };

    const nodes = try node.splitNode(gpa);
    defer gpa.free(nodes);

    try std.testing.expect(nodes.len == 2);
    try std.testing.expect(nodes[0].textType == .text);
    try std.testing.expect(nodes[1].textType == .bold);
}

test "bold embedded in text" {
    const gpa = std.testing.allocator;
    const node = TextNode{
        .text = "just some **bold** text",
        .textType = TextType.text,
        .url = "",
    };

    const nodes = try node.splitNode(gpa);
    defer gpa.free(nodes);

    try std.testing.expect(nodes.len == 3);
    try std.testing.expect(nodes[0].textType == .text);
    try std.testing.expect(nodes[1].textType == .bold);
    try std.testing.expect(nodes[2].textType == .text);
}

test "unterminated bold tag errors" {
    const gpa = std.testing.allocator;
    const node = TextNode{
        .text = "just some **bold* text",
        .textType = TextType.text,
        .url = "",
    };

    const nodes = node.splitNode(gpa);

    try std.testing.expectError(error.InvalidMarkdown, nodes);
}

test "italic embedded in text" {
    const gpa = std.testing.allocator;
    const node = TextNode{
        .text = "just some _italic_ text",
        .textType = TextType.text,
        .url = "",
    };

    const nodes = try node.splitNode(gpa);
    defer gpa.free(nodes);

    try std.testing.expect(nodes.len == 3);
    try std.testing.expect(nodes[0].textType == .text);
    try std.testing.expect(nodes[1].textType == .italic);
    try std.testing.expect(nodes[2].textType == .text);
}

test "unterminated italic tag errors" {
    const gpa = std.testing.allocator;
    const node = TextNode{
        .text = "just some _italic text",
        .textType = TextType.text,
        .url = "",
    };

    const nodes = node.splitNode(gpa);

    try std.testing.expectError(error.InvalidMarkdown, nodes);
}

test "code embedded in text" {
    const gpa = std.testing.allocator;
    const node = TextNode{
        .text = "just some `code` text",
        .textType = TextType.text,
        .url = "",
    };

    const nodes = try node.splitNode(gpa);
    defer gpa.free(nodes);

    try std.testing.expect(nodes.len == 3);
    try std.testing.expect(nodes[0].textType == .text);
    try std.testing.expect(nodes[1].textType == .code);
    try std.testing.expect(nodes[2].textType == .text);
}

test "unterminated code tag errors" {
    const gpa = std.testing.allocator;
    const node = TextNode{
        .text = "just some `italic text",
        .textType = TextType.text,
        .url = "",
    };

    const nodes = node.splitNode(gpa);

    try std.testing.expectError(error.InvalidMarkdown, nodes);
}

test "link embedded in text" {
    const gpa = std.testing.allocator;
    const node = TextNode{
        .text = "just some [click me](https://crimsonhexagon.us) text",
        .textType = TextType.text,
        .url = "",
    };

    const nodes = try node.splitNode(gpa);
    defer gpa.free(nodes);

    try std.testing.expect(nodes.len == 3);
    try std.testing.expect(nodes[0].textType == .text);
    try std.testing.expect(nodes[1].textType == .link);
    try std.testing.expect(nodes[2].textType == .text);
    try std.testing.expectEqualStrings("just some ", nodes[0].text);
    try std.testing.expectEqualStrings("click me", nodes[1].text);
    try std.testing.expectEqualStrings("https://crimsonhexagon.us", nodes[1].url);
    try std.testing.expectEqualStrings(" text", nodes[2].text);
}

test "image embedded in text" {
    const gpa = std.testing.allocator;
    const node = TextNode{
        .text = "just some ![an image](https://crimsonhexagon.us/image.png) text",
        .textType = TextType.text,
        .url = "",
    };

    const nodes = try node.splitNode(gpa);
    defer gpa.free(nodes);

    try std.testing.expect(nodes.len == 3);
    try std.testing.expect(nodes[0].textType == .text);
    try std.testing.expect(nodes[1].textType == .image);
    try std.testing.expect(nodes[2].textType == .text);
    try std.testing.expectEqualStrings("just some ", nodes[0].text);
    try std.testing.expectEqualStrings("an image", nodes[1].text);
    try std.testing.expectEqualStrings("https://crimsonhexagon.us/image.png", nodes[1].url);
    try std.testing.expectEqualStrings(" text", nodes[2].text);
}

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
