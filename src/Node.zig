const std = @import("std");
const HtmlNode = @import("HtmlNode.zig").HtmlNode;
const LeafNode = @import("LeafNode.zig").LeafNode;
const TextNode = @import("TextNode.zig").TextNode;
const ParentNode = @import("ParentNode.zig").ParentNode;

pub const Node = union(enum) {
    html: HtmlNode,
    leaf: LeafNode,
    text: TextNode,
    parent: ParentNode,

    pub fn toHtml(self: Node, allocator: std.mem.Allocator) anyerror![]u8 {
        return switch (self) {
            .leaf => |leaf| try leaf.toHtml(allocator),
            .parent => |parent| try parent.toHtml(allocator),
            .text => @panic("Cannot convert TextNode to HTML"),
            .html => @panic("HTML nodes are abstract and cannot be converted to HTML"),
        };
    }
};

pub const NodeError = error{
    MustHaveChildren,
};
