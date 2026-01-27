const std = @import("std");
const LeafNode = @import("LeafNode.zig").LeafNode;
const Node = @import("Node.zig").Node;
const ParentNode = @import("ParentNode.zig").ParentNode;
const TextNodeParser = @import("TextNodeParser.zig").TextNodeParser;
const TextType = @import("TextNode.zig").TextType;

pub const BlockType = enum {
    paragraph,
    heading,
    code,
    quote,
    unordered_list,
    ordered_list,
};

const BlockResult = union(enum) {
    single: []const u8,
    list: [][]const u8,

    pub fn deinit(self: BlockResult, allocator: std.mem.Allocator) void {
        switch (self) {
            .single => |s| allocator.free(s),
            .list => |items| {
                for (items) |item| {
                    allocator.free(item);
                }
                allocator.free(items);
            },
        }
    }
};

pub const MarkdownParser = struct {
    document: []const u8,

    fn markdown_to_blocks(self: *const MarkdownParser, allocator: std.mem.Allocator) ![][]const u8 {
        var it = std.mem.splitSequence(u8, self.document, "\n\n");

        var list = std.ArrayList([]const u8).empty;
        errdefer list.deinit(allocator);

        while (it.next()) |item| {
            const trimmed_item = std.mem.trim(u8, item, " \t\n\r");
            if (trimmed_item.len > 0) {
                try list.append(allocator, trimmed_item);
            }
        }

        return list.toOwnedSlice(allocator);
    }

    fn get_block_type(block: []const u8) !BlockType {
        if (std.mem.startsWith(u8, block, "> ")) {
            return .quote;
        } else if (std.mem.startsWith(u8, block, "```\n")) {
            if (std.mem.endsWith(u8, block, "\n```")) {
                return .code;
            }
        } else if (std.mem.startsWith(u8, block, "#")) {
            if (block.len < 3) return .paragraph;

            var count: usize = 0;
            while (count < 7 and count < block.len) {
                if (block[count] == '#') {
                    count += 1;
                } else if (block[count] == ' ' and block.len > count) {
                    return .heading;
                } else {
                    return .paragraph;
                }
            }
        } else if (std.mem.startsWith(u8, block, "- ")) {
            var it = std.mem.splitAny(u8, block, "\n");
            while (it.next()) |line| {
                if (!std.mem.startsWith(u8, line, "- ")) return .paragraph;
            }
            return .unordered_list;
        } else if (std.mem.startsWith(u8, block, "1. ")) {
            var idx: usize = 1;
            var it = std.mem.splitAny(u8, block, "\n");
            var buffer: [6]u8 = undefined;
            while (it.next()) |line| {
                const written = try std.fmt.bufPrint(&buffer, "{d}. ", .{idx});
                if (!std.mem.startsWith(u8, line, written)) return .paragraph;
                idx += 1;
            }
            return .ordered_list;
        }
        return .paragraph;
    }

    fn handleCode(allocator: std.mem.Allocator, codeBlock: []const u8) !BlockResult {
        var list = std.ArrayList(u8).empty;
        errdefer list.deinit(allocator);

        const len = codeBlock.len;
        try list.appendSlice(allocator, codeBlock[4 .. len - 3]);
        return .{ .single = try list.toOwnedSlice(allocator) };
    }

    fn handleParagraph(allocator: std.mem.Allocator, paragraph: []const u8) !BlockResult {
        var list = std.ArrayList(u8).empty;
        errdefer list.deinit(allocator);
        try list.appendSlice(allocator, paragraph);
        std.mem.replaceScalar(u8, list.items, '\n', ' ');
        std.mem.replaceScalar(u8, list.items, '\t', ' ');
        return .{ .single = try list.toOwnedSlice(allocator) };
    }

    fn handleHeading(allocator: std.mem.Allocator, paragraph: []const u8) !BlockResult {
        var list = std.ArrayList(u8).empty;
        errdefer list.deinit(allocator);
        var count: usize = 0;
        while (paragraph[count] == '#') {
            count += 1;
        }
        try list.appendSlice(allocator, paragraph[count + 1 ..]);
        std.mem.replaceScalar(u8, list.items, '\t', ' ');
        return .{ .single = try list.toOwnedSlice(allocator) };
    }

    fn handleQuote(allocator: std.mem.Allocator, paragraph: []const u8) !BlockResult {
        var list = std.ArrayList(u8).empty;
        errdefer list.deinit(allocator);
        try list.appendSlice(allocator, paragraph);
        const slice = try list.toOwnedSlice(allocator);
        defer allocator.free(slice);
        std.mem.replaceScalar(u8, slice, '>', ' ');
        std.mem.replaceScalar(u8, slice, '\n', ' ');
        std.mem.replaceScalar(u8, slice, '\t', ' ');
        const new_slice = std.mem.collapseRepeats(u8, slice, ' ');
        const trimmed = std.mem.trim(u8, new_slice, " ");
        var result = std.ArrayList(u8).empty;
        try result.appendSlice(allocator, trimmed);
        return .{ .single = try result.toOwnedSlice(allocator) };
    }

    fn handleList(allocator: std.mem.Allocator, paragraph: []const u8) !BlockResult {
        var linesResult = std.ArrayList([]const u8).empty;
        errdefer linesResult.deinit(allocator);

        var linesIterator = std.mem.splitAny(u8, paragraph, "\n");

        while (linesIterator.next()) |line| {
            const toTrim = std.mem.indexOf(u8, line, " ") orelse @panic("list with no space");
            const result = try allocator.alloc(u8, line.len - toTrim - 1);
            std.mem.copyForwards(u8, result, line[toTrim + 1 ..]);
            try linesResult.append(allocator, result);
        }

        return .{ .list = try linesResult.toOwnedSlice(allocator) };
    }

    pub fn parse(self: MarkdownParser, allocator: std.mem.Allocator) !ParentNode {
        const blocks = try self.markdown_to_blocks(allocator);
        defer allocator.free(blocks);

        var list = std.ArrayList(Node).empty;
        errdefer list.deinit(allocator);

        for (blocks) |block| {
            const t: BlockType = try get_block_type(block);

            const textType: TextType = switch (t) {
                .code => .code,
                else => .text,
            };

            const parsedBlock = switch (t) {
                .code => try handleCode(allocator, block),
                .paragraph => try handleParagraph(allocator, block),
                .heading => try handleHeading(allocator, block),
                .quote => try handleQuote(allocator, block),
                .ordered_list, .unordered_list => try handleList(allocator, block),
            };
            defer parsedBlock.deinit(allocator);

            const parentTag = switch (t) {
                .paragraph => "p",
                .code => "pre",
                .heading => headingBlk: {
                    var count: usize = 0;
                    while (block[count] == '#') {
                        count += 1;
                    }
                    break :headingBlk switch (count) {
                        1 => "h1",
                        2 => "h2",
                        3 => "h3",
                        4 => "h4",
                        5 => "h5",
                        6 => "h6",
                        else => @panic("Unreachable"),
                    };
                },
                .quote => "blockquote",
                .ordered_list => "ol",
                .unordered_list => "ul",
            };

            var childList = std.ArrayList(Node).empty;

            switch (parsedBlock) {
                .single => |singleBlock| {
                    var parser = try TextNodeParser.init(.{ .text = singleBlock, .textType = textType, .url = "" });
                    const result = try parser.parse(allocator);
                    defer allocator.free(result);
                    for (result) |child| {
                        const node: Node = .{ .leaf = try child.toNode(allocator) };
                        try childList.append(allocator, node);
                    }
                },
                .list => |listBlock| {
                    for (listBlock) |item| {
                        var innerChildList = std.ArrayList(Node).empty;
                        var parser = try TextNodeParser.init(.{ .text = item, .textType = textType, .url = "" });
                        const result = try parser.parse(allocator);
                        defer allocator.free(result);
                        for (result) |child| {
                            const node: Node = .{ .leaf = try child.toNode(allocator) };
                            try innerChildList.append(allocator, node);
                        }
                        const parent: Node = . { .parent = try ParentNode.init(allocator, "li", try innerChildList.toOwnedSlice(allocator)) };
                        try childList.append(allocator, parent);
                    }
                },
            }
            const parentNode = try ParentNode.init(allocator, parentTag, try childList.toOwnedSlice(allocator));
            try list.append(allocator, .{ .parent = parentNode });
        }

        const node = try ParentNode.init(allocator, "div", try list.toOwnedSlice(allocator));

        return node;
    }
};

test "three * list" {
    const gpa = std.testing.allocator;
    const parser = MarkdownParser{
        .document =
        \\- list item
        \\- list item
        \\- list item
        ,
    };

    var result = try parser.parse(gpa);
    defer result.deinit(gpa);

    const html = try result.toHtml(gpa);
    defer gpa.free(html);

    try std.testing.expectEqualStrings("<div><ul><li>list item</li><li>list item</li><li>list item</li></ul></div>", html);
}

test "three 1 list" {
    const gpa = std.testing.allocator;
    const parser = MarkdownParser{
        .document =
        \\1. list item
        \\2. list item
        \\3. list item
        ,
    };

    var result = try parser.parse(gpa);
    defer result.deinit(gpa);

    const html = try result.toHtml(gpa);
    defer gpa.free(html);

    try std.testing.expectEqualStrings("<div><ol><li>list item</li><li>list item</li><li>list item</li></ol></div>", html);
}

test "multi-line quote of doom" {
    const gpa = std.testing.allocator;
    const parser = MarkdownParser{
        .document =
        \\> This is
        \\ a multiline quote
        \\> that really
        \\> hates
        \\implementers
        ,
    };

    var result = try parser.parse(gpa);
    defer result.deinit(gpa);

    const html = try result.toHtml(gpa);
    defer gpa.free(html);

    try std.testing.expectEqualStrings("<div><blockquote>This is a multiline quote that really hates implementers</blockquote></div>", html);
}

test "test heading" {
    const gpa = std.testing.allocator;
    const parser = MarkdownParser{
        .document = "### This is a heading",
    };

    var result = try parser.parse(gpa);
    defer result.deinit(gpa);

    const html = try result.toHtml(gpa);
    defer gpa.free(html);

    try std.testing.expectEqualStrings("<div><h3>This is a heading</h3></div>", html);
}

test "test paragraphs" {
    const gpa = std.testing.allocator;
    const parser = MarkdownParser{
        .document =
        \\This is **bolded** paragraph
        \\text in a p
        \\tag here
        \\
        \\This is another paragraph with _italic_ text and `code` here
        \\
        ,
    };

    var result = try parser.parse(gpa);
    defer result.deinit(gpa);

    const html = try result.toHtml(gpa);
    defer gpa.free(html);

    try std.testing.expectEqualStrings("<div><p>This is <b>bolded</b> paragraph text in a p tag here</p><p>This is another paragraph with <i>italic</i> text and <code>code</code> here</p></div>", html);
}

test "test codeblock" {
    const gpa = std.testing.allocator;
    const parser = MarkdownParser{
        .document =
        \\```
        \\This is text that _should_ remain
        \\the **same** even with inline stuff
        \\```
        ,
    };

    var result = try parser.parse(gpa);
    defer result.deinit(gpa);

    const html = try result.toHtml(gpa);
    defer gpa.free(html);

    try std.testing.expectEqualStrings("<div><pre><code>This is text that _should_ remain\nthe **same** even with inline stuff\n</code></pre></div>", html);
}

test "one 1 list" {
    const str = "1. list item";
    const t = try MarkdownParser.get_block_type(str);
    try std.testing.expectEqual(BlockType.ordered_list, t);
}

test "six 1 list" {
    const str =
        \\1. list item
        \\2. list item
        \\3. list item
        \\4. list item
        \\5. list item
        \\6. list item
    ;
    const t = try MarkdownParser.get_block_type(str);
    try std.testing.expectEqual(BlockType.ordered_list, t);
}

test "six 1 almost list" {
    const str =
        \\1. list item
        \\2. list item
        \\3. list item
        \\4.list item that forgot its space
        \\5. list item
        \\6. list item
    ;
    const t = try MarkdownParser.get_block_type(str);
    try std.testing.expectEqual(BlockType.paragraph, t);
}

test "one - list" {
    const str = "- list item";
    const t = try MarkdownParser.get_block_type(str);
    try std.testing.expectEqual(BlockType.unordered_list, t);
}

test "six - list" {
    const str =
        \\- list item
        \\- list item
        \\- list item
        \\- list item
        \\- list item
        \\- list item
    ;
    const t = try MarkdownParser.get_block_type(str);
    try std.testing.expectEqual(BlockType.unordered_list, t);
}

test "six - not quite a list" {
    const str =
        \\- list item
        \\- list item
        \\- list item
        \\list item I forgor my -
        \\- list item
        \\- list item
    ;
    const t = try MarkdownParser.get_block_type(str);
    try std.testing.expectEqual(BlockType.paragraph, t);
}

test "one # heading" {
    const str = "# heading 1";
    const t = try MarkdownParser.get_block_type(str);
    try std.testing.expectEqual(BlockType.heading, t);
}

test "six # heading" {
    const str = "###### heading 6";
    const t = try MarkdownParser.get_block_type(str);
    try std.testing.expectEqual(BlockType.heading, t);
}

test "seven # heading is a paragraph" {
    const str = "####### heading 7";
    const t = try MarkdownParser.get_block_type(str);
    try std.testing.expectEqual(BlockType.paragraph, t);
}

test "one # heading without text is a paragraph" {
    const str = "# ";
    const t = try MarkdownParser.get_block_type(str);
    try std.testing.expectEqual(BlockType.paragraph, t);
}

test "one # heading without space is a paragraph" {
    const str = "#nospace";
    const t = try MarkdownParser.get_block_type(str);
    try std.testing.expectEqual(BlockType.paragraph, t);
}

test "heading with multiple spaces after #" {
    const str = "#   heading";
    const t = try MarkdownParser.get_block_type(str);
    try std.testing.expectEqual(BlockType.heading, t);
}

test "line with only hashes" {
    const str = "###";
    const t = try MarkdownParser.get_block_type(str);
    try std.testing.expectEqual(BlockType.paragraph, t);
}

test "block that starts with > is a quote block" {
    const str = "> single-line quote";

    const t = try MarkdownParser.get_block_type(str);

    try std.testing.expectEqual(BlockType.quote, t);
}

test "what is a multi-line quote" {
    const str =
        \\> the first line
        \\another line
    ;

    const t = try MarkdownParser.get_block_type(str);

    try std.testing.expectEqual(BlockType.quote, t);
}

test "why is a multi-line quote" {
    const str =
        \\> This is
        \\ a mutliline quote
        \\> that really
        \\> hates
        \\implementers
    ;

    const t = try MarkdownParser.get_block_type(str);

    try std.testing.expectEqual(BlockType.quote, t);
}

test "this is a multi-line code block" {
    const str =
        \\```
        \\This is
        \\a mutliline code block
        \\and not a paragraph
        \\```
    ;

    const t = try MarkdownParser.get_block_type(str);

    try std.testing.expectEqual(BlockType.code, t);
}

test "this is not a multi-line code block but a paragraph" {
    const str =
        \\```
        \\This is
        \\a mutliline code block
        \\and not a paragraph
    ;

    const t = try MarkdownParser.get_block_type(str);

    try std.testing.expectEqual(BlockType.paragraph, t);
}

test "markdown to blocks" {
    const gpa = std.testing.allocator;
    const str =
        \\This is **bolded** paragraph
        \\
        \\This is another paragraph with _italic_ text and `code` here
        \\This is the same paragraph on a new line
        \\
        \\- This is a list
        \\- with items
    ;

    const parser = MarkdownParser{
        .document = str,
    };

    const result = try parser.markdown_to_blocks(gpa);
    defer gpa.free(result);

    try std.testing.expect(result.len == 3);
}
