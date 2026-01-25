const std = @import("std");
const Node = @import("Node.zig").Node;
const NodeError = @import("Node.zig").NodeError;

pub const ParentNode = struct {
    tag: []const u8,
    children: []const Node,
    props: std.StringHashMap([]const u8),

    pub fn init(
        allocator: std.mem.Allocator,
        tag: []const u8,
        children: []const Node,
    ) !ParentNode {
        const self = ParentNode{
            .tag = tag,
            .children = children,
            .props = std.StringHashMap([]const u8).init(allocator),
        };

        return self;
    }

    pub fn deinit(self: *ParentNode) void {
        self.props.deinit();
    }

    pub fn propsToHtml(
        self: ParentNode,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        var iterator = self.props.iterator();
        var list = std.ArrayList(u8).empty;
        errdefer list.deinit(allocator);

        const writer = list.writer(allocator);

        while (iterator.next()) |entry| {
            try writer.print(" {s}=\"{s}\"", .{ entry.key_ptr.*, entry.value_ptr.* });
        }

        return list.toOwnedSlice(allocator);
    }

    pub fn toHtml(
        self: ParentNode,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        if (self.children.len == 0) {
            return NodeError.MustHaveChildren;
        }
        var list = std.ArrayList(u8).empty;
        errdefer list.deinit(allocator);

        const writer = list.writer(allocator);

        const propsString = try self.propsToHtml(allocator);
        defer allocator.free(propsString);
        try writer.print("<{s}{s}>", .{ self.tag, propsString });

        for (self.children) |child| {
            const result = try child.toHtml(allocator);
            defer allocator.free(result);
            try writer.print("{s}", .{result});
        }

        try writer.print("</{s}>", .{self.tag});

        return list.toOwnedSlice(allocator);
    }
};

test "test parent node with zero children" {
    const gpa = std.testing.allocator;
    var parentNode = try ParentNode.init(gpa, "div", &.{});
    defer parentNode.deinit();

    const result = parentNode.toHtml(gpa);
    try std.testing.expectError(NodeError.MustHaveChildren, result);
}

test "test parent node with one child" {
    const LeafNode = @import("LeafNode.zig").LeafNode;
    const gpa = std.testing.allocator;
    var childNode = try LeafNode.init(gpa, "p", "Hello, world!", false);
    defer childNode.deinit();

    var parentNode = try ParentNode.init(gpa, "div", &[_]Node{.{ .leaf = childNode }});
    defer parentNode.deinit();

    const result = try parentNode.toHtml(gpa);
    defer gpa.free(result);
    try std.testing.expectEqualStrings("<div><p>Hello, world!</p></div>", result);
}

test "test parent node with one grandchild" {
    const LeafNode = @import("LeafNode.zig").LeafNode;
    const gpa = std.testing.allocator;
    var childNode = try LeafNode.init(gpa, "p", "Hello, world!", false);
    defer childNode.deinit();

    var parentNode = try ParentNode.init(gpa, "div", &[_]Node{.{ .leaf = childNode }});
    defer parentNode.deinit();

    var grandparentNode = try ParentNode.init(gpa, "span", &[_]Node{.{ .parent = parentNode }});
    defer grandparentNode.deinit();

    const result = try grandparentNode.toHtml(gpa);
    defer gpa.free(result);
    try std.testing.expectEqualStrings("<span><div><p>Hello, world!</p></div></span>", result);
}

test "test parent node with two children" {
    const LeafNode = @import("LeafNode.zig").LeafNode;
    const gpa = std.testing.allocator;
    var childNode = try LeafNode.init(gpa, "p", "Hello, world!", false);
    defer childNode.deinit();

    var childNode2 = try LeafNode.init(gpa, "h1", "Goodbye, world!", false);
    defer childNode2.deinit();

    var parentNode = try ParentNode.init(gpa, "div", &[_]Node{ .{ .leaf = childNode }, .{ .leaf = childNode2 } });
    defer parentNode.deinit();

    const result = try parentNode.toHtml(gpa);
    defer gpa.free(result);
    try std.testing.expectEqualStrings("<div><p>Hello, world!</p><h1>Goodbye, world!</h1></div>", result);
}
