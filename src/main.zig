const std = @import("std");
const fmt = @import("fmt");
const ssg = @import("ssg");
const TextNode = ssg.TextNode;
const TextType = ssg.TextType;
const HtmlNode = ssg.HtmlNode;

pub fn main() !void {
    const my_text_node: TextNode = .{ .text = "This is some anchor text", .textType = TextType.link, .url = "https://www.boot.dev" };
    std.debug.print("{f}\n", .{my_text_node});
}
