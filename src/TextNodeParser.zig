const std = @import("std");
const TextNode = @import("TextNode.zig").TextNode;
const TextType = @import("TextNode.zig").TextType;

pub const TextNodeParser = struct {
    index: usize,
    current: usize,
    text: []const u8,
    in_tag: ?TextType,
    textNodeType: TextType,
    url: []const u8,

    pub fn init(
        textNode: TextNode,
    ) !TextNodeParser {
        const self = TextNodeParser{
            .index = 0,
            .current = 0,
            .in_tag = null,
            .text = textNode.text,
            .textNodeType = textNode.textType,
            .url = textNode.url,
        };

        return self;
    }

    fn peek(
        self: *const TextNodeParser,
        c: u8,
    ) bool {
        return self.index + 1 < self.text.len and self.text[self.index + 1] == c;
    }

    fn advance(
        self: *TextNodeParser,
        by: usize,
    ) void {
        self.index += by;
        self.current = self.index;
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

    pub fn parse(
        self: *TextNodeParser,
        allocator: std.mem.Allocator,
    ) ![]TextNode {
        var list = std.ArrayList(TextNode).empty;
        errdefer list.deinit(allocator);

        if (self.textNodeType != .text) {
            const tmp = TextNode{ .text = self.text, .textType = self.textNodeType, .url = self.url };
            try list.append(allocator, tmp);
            return list.toOwnedSlice(allocator);
        }

        self.index = 0;
        self.current = 0;
        self.in_tag = null;

        while (self.index < self.text.len) {
            switch (self.text[self.index]) {
                '*' => {
                    const is_double_star = self.peek('*');
                    if (is_double_star and self.in_tag == null) {
                        self.in_tag = .bold;
                        try emit(allocator, &list, self.text[self.current..self.index], .text, null);
                        self.advance(2);
                    } else if (is_double_star and self.in_tag == .bold) {
                        self.in_tag = null;
                        try emit(allocator, &list, self.text[self.current..self.index], .bold, null);
                        self.advance(2);
                    } else if (is_double_star) {
                        return error.InvalidMarkdown;
                    } else {
                        self.index += 1;
                    }
                },
                '_' => {
                    if (self.in_tag == null) {
                        self.in_tag = .italic;
                        try emit(allocator, &list, self.text[self.current..self.index], .text, null);
                        self.advance(1);
                    } else if (self.in_tag == .italic) {
                        self.in_tag = null;
                        try emit(allocator, &list, self.text[self.current..self.index], .italic, null);
                        self.advance(1);
                    } else {
                        return error.InvalidMarkdown;
                    }
                },
                '`' => {
                    if (self.in_tag == null) {
                        self.in_tag = .code;
                        try emit(allocator, &list, self.text[self.current..self.index], .text, null);
                        self.advance(1);
                    } else if (self.in_tag == .code) {
                        self.in_tag = null;
                        try emit(allocator, &list, self.text[self.current..self.index], .code, null);
                        self.advance(1);
                    } else {
                        return error.InvalidMarkdown;
                    }
                },
                '[' => {
                    if (self.in_tag != null) return error.InvalidMarkdown;

                    try emit(allocator, &list, self.text[self.current..self.index], .text, null);
                    self.advance(1);
                    self.index += std.mem.indexOf(u8, self.text[self.current..], "]") orelse return error.InvalidMarkdown;
                    const value = switch (self.peek('(')) {
                        true => self.text[self.current..self.index],
                        false => return error.InvalidMarkdown,
                    };
                    self.advance(2);
                    self.index += std.mem.indexOf(u8, self.text[self.current..], ")") orelse return error.InvalidMarkdown;
                    const url = self.text[self.current..self.index];
                    try emit(allocator, &list, value, .link, url);
                    self.advance(1);
                },
                '!' => {
                    if (!self.peek('[')) {
                        self.index += 1;
                        continue;
                    }

                    if (self.in_tag != null) return error.InvalidMarkdown;

                    try emit(allocator, &list, self.text[self.current..self.index], .text, null);
                    self.advance(2);
                    self.index += std.mem.indexOf(u8, self.text[self.current..], "]") orelse return error.InvalidMarkdown;
                    const value = switch (self.peek('(')) {
                        true => self.text[self.current..self.index],
                        false => return error.InvalidMarkdown,
                    };
                    self.advance(2);
                    self.index += std.mem.indexOf(u8, self.text[self.current..], ")") orelse return error.InvalidMarkdown;
                    const url = self.text[self.current..self.index];
                    try emit(allocator, &list, value, .image, url);
                    self.advance(1);
                },
                else => self.index += 1,
            }
        }

        if (self.in_tag != null) {
            return error.InvalidMarkdown;
        }

        if (self.current < self.text.len) {
            try emit(allocator, &list, self.text[self.current..], .text, null);
        }

        return list.toOwnedSlice(allocator);
    }

    pub fn extract(self: *TextNodeParser, allocator: std.mem.Allocator, textType: TextType) ![]struct { []const u8, []const u8 } {
        if (textType != .image and textType != .link) return error.NotSupported;
        const nodes = try self.parse(allocator);
        defer allocator.free(nodes);
        var list = std.ArrayList(struct { []const u8, []const u8 }).empty;
        errdefer list.deinit(allocator);

        for (nodes) |node| {
            if (node.textType == textType) {
                try list.append(allocator, .{ node.text, node.url });
            }
        }

        return list.toOwnedSlice(allocator);
    }
};

test "the whole thing" {
    const gpa = std.testing.allocator;
    const node = TextNode{
        .text = "This is **text** with an _italic_ word and a `code block` and an ![obi wan image](https://i.imgur.com/fJRm4Vk.jpeg) and a [link](https://boot.dev)",
        .textType = TextType.text,
        .url = "",
    };

    var parser = try TextNodeParser.init(node);
    const images = try parser.parse(gpa);
    defer gpa.free(images);

    try std.testing.expect(images.len == 10);
}

test "extract images from markdown" {
    const gpa = std.testing.allocator;
    const node = TextNode{
        .text = "This is text with a ![rick roll](https://i.imgur.com/aKaOqIh.gif) and ![obi wan](https://i.imgur.com/fJRm4Vk.jpeg)",
        .textType = TextType.text,
        .url = "",
    };

    var parser = try TextNodeParser.init(node);
    const images = try parser.extract(gpa, .image);
    defer gpa.free(images);

    try std.testing.expect(images.len == 2);
    try std.testing.expectEqualStrings("rick roll", images[0][0]);
    try std.testing.expectEqualStrings("https://i.imgur.com/aKaOqIh.gif", images[0][1]);
    try std.testing.expectEqualStrings("obi wan", images[1][0]);
    try std.testing.expectEqualStrings("https://i.imgur.com/fJRm4Vk.jpeg", images[1][1]);
}

test "extract links from markdown" {
    const gpa = std.testing.allocator;
    const node = TextNode{
        .text = "This is text with a link [to boot dev](https://www.boot.dev) and [to youtube](https://www.youtube.com/@bootdotdev)",
        .textType = TextType.text,
        .url = "",
    };

    var parser = try TextNodeParser.init(node);
    const images = try parser.extract(gpa, .link);
    defer gpa.free(images);

    try std.testing.expect(images.len == 2);
    try std.testing.expectEqualStrings("to boot dev", images[0][0]);
    try std.testing.expectEqualStrings("https://www.boot.dev", images[0][1]);
    try std.testing.expectEqualStrings("to youtube", images[1][0]);
    try std.testing.expectEqualStrings("https://www.youtube.com/@bootdotdev", images[1][1]);
}

test "tag ends at end of line - 1" {
    const gpa = std.testing.allocator;
    const node = TextNode{
        .text = "just some text, **bold**!",
        .textType = TextType.text,
        .url = "",
    };

    var parser = try TextNodeParser.init(node);

    const nodes = try parser.parse(gpa);
    defer gpa.free(nodes);

    try std.testing.expect(nodes.len == 3);
    try std.testing.expect(nodes[0].textType == .text);
    try std.testing.expect(nodes[1].textType == .bold);
    try std.testing.expect(nodes[2].textType == .text);
}

test "tag ends at end of line" {
    const gpa = std.testing.allocator;
    const node = TextNode{
        .text = "just some **bold text**",
        .textType = TextType.text,
        .url = "",
    };

    var parser = try TextNodeParser.init(node);

    const nodes = try parser.parse(gpa);
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

    var parser = try TextNodeParser.init(node);

    const nodes = try parser.parse(gpa);
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

    var parser = try TextNodeParser.init(node);
    const nodes = parser.parse(gpa);

    try std.testing.expectError(error.InvalidMarkdown, nodes);
}

test "italic embedded in text" {
    const gpa = std.testing.allocator;
    const node = TextNode{
        .text = "just some _italic_ text",
        .textType = TextType.text,
        .url = "",
    };

    var parser = try TextNodeParser.init(node);
    const nodes = try parser.parse(gpa);
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

    var parser = try TextNodeParser.init(node);
    const nodes = parser.parse(gpa);

    try std.testing.expectError(error.InvalidMarkdown, nodes);
}

test "code embedded in text" {
    const gpa = std.testing.allocator;
    const node = TextNode{
        .text = "just some `code` text",
        .textType = TextType.text,
        .url = "",
    };

    var parser = try TextNodeParser.init(node);
    const nodes = try parser.parse(gpa);
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

    var parser = try TextNodeParser.init(node);
    const nodes = parser.parse(gpa);

    try std.testing.expectError(error.InvalidMarkdown, nodes);
}

test "link embedded in text" {
    const gpa = std.testing.allocator;
    const node = TextNode{
        .text = "just some [click me](https://crimsonhexagon.us) text",
        .textType = TextType.text,
        .url = "",
    };

    var parser = try TextNodeParser.init(node);
    const nodes = try parser.parse(gpa);
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

    var parser = try TextNodeParser.init(node);
    const nodes = try parser.parse(gpa);
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
