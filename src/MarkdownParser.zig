const std = @import("std");
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

    pub fn parse(self: MarkdownParser, allocator: std.mem.Allocator) ![]const u8 {
        const blocks = try self.markdown_to_blocks(allocator);
        defer allocator.free(blocks);

        var list = std.ArrayList(u8).empty;
        errdefer list.deinit(allocator);

        for (blocks) |block| {
            const t: BlockType = try get_block_type(block);

            const textType: TextType = switch (t) {
                .code => .code,
                else => .text,
            };
            var parser = try TextNodeParser.init(.{ .text = block, .textType = textType, .url = "" });
            const result = try parser.parse(allocator);
            defer allocator.free(result);
            for (result) |res| {
                const html = try res.toHtml(allocator);
                defer allocator.free(html);
                try list.appendSlice(allocator, html);
            }
        }

        return list.toOwnedSlice(allocator);
    }
};

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

    const result = try parser.parse(gpa);
    defer gpa.free(result);

    try std.testing.expect(true);
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
