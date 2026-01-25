//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
pub const TextNode = @import("TextNode.zig").TextNode;
pub const TextType = @import("TextNode.zig").TextType;
pub const HtmlNode = @import("HtmlNode.zig").HtmlNode;
pub const LeafNode = @import("LeafNode.zig").LeafNode;
pub const ParentNode = @import("ParentNode.zig").ParentNode;
pub const Node = @import("Node.zig").Node;
pub const NodeError = @import("Node.zig").NodeError;

test {
    _ = @import("TextNode.zig");
    _ = @import("HtmlNode.zig");
    _ = @import("LeafNode.zig");
}
