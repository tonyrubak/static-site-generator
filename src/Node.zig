const std = @import("std");
const HtmlNode = @import("HtmlNode.zig").HtmlNode;
const LeafNode = @import("LeafNode.zig").LeafNode;
const ParentNode = @import("ParentNode.zig").ParentNode;

pub const Node = union(enum) {
    html: HtmlNode,
    leaf: LeafNode,
    parent: ParentNode,

    pub fn toHtml(self: Node, allocator: std.mem.Allocator) anyerror![]u8 {
        return switch (self) {
            .leaf => |leaf| try leaf.toHtml(allocator),
            .parent => |parent| try parent.toHtml(allocator),
            .html => @panic("HTML nodes are abstract and cannot be converted to HTML"),
        };
    }

    pub fn deinit(self: *Node) void {
        return switch (self.*) {
            .leaf => |*leaf| leaf.deinit(),
            else => {},
        };
    }
};

pub const NodeError = error{
    VoidElementHasContent,
    MustHaveChildren,
};
