const std = @import("std");
const NodeError = @import("Node.zig").NodeError;

pub const LeafNode = struct {
    tag: []const u8,
    value: []const u8,
    props: std.StringHashMap([]const u8),
    is_void: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        tag: []const u8,
        value: []const u8,
        is_void: bool,
    ) !LeafNode {
        const self = LeafNode{
            .tag = try allocator.dupe(u8, tag),
            .value = try allocator.dupe(u8, value),
            .props = std.StringHashMap([]const u8).init(allocator),
            .is_void = is_void,
        };

        return self;
    }

    pub fn deinit(self: *LeafNode, allocator: std.mem.Allocator) void {
        var it = self.props.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.value_ptr.*);
        }
        allocator.free(self.tag);
        allocator.free(self.value);
        self.props.deinit();
    }

    pub fn propsToHtml(
        self: LeafNode,
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
        self: LeafNode,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        if (self.is_void and self.value.len > 0) {
            return NodeError.VoidElementHasContent;
        }
        var list = std.ArrayList(u8).empty;
        errdefer list.deinit(allocator);

        const writer = list.writer(allocator);

        const propsString = try self.propsToHtml(allocator);
        defer allocator.free(propsString);
        if (self.tag.len > 0) {
            try writer.print("<{s}{s}>", .{ self.tag, propsString });
        }
        try writer.print("{s}", .{self.value});
        if (self.tag.len > 0) {
            try writer.print("</{s}>", .{self.tag});
        }

        return list.toOwnedSlice(allocator);
    }
};

test "test leaf node with no properties" {
    const gpa = std.testing.allocator;
    var node = try LeafNode.init(gpa, "p", "Hello, world!", false);
    defer node.deinit(gpa);

    const result = try node.toHtml(gpa);
    defer gpa.free(result);
    try std.testing.expectEqualStrings("<p>Hello, world!</p>", result);
}

test "test leaf node with 1 property" {
    const gpa = std.testing.allocator;
    var node = try LeafNode.init(gpa, "h1", "Hello, world!", false);
    defer node.deinit(gpa);

    try node.props.put("class", try gpa.dupe(u8, "text-danger"));

    const result = try node.toHtml(gpa);
    defer gpa.free(result);
    try std.testing.expectEqualStrings("<h1 class=\"text-danger\">Hello, world!</h1>", result);
}

test "test leaf node with 2 properties" {
    const gpa = std.heap.page_allocator;
    var node = try LeafNode.init(gpa, "h1", "Hello, world!", false);
    defer node.deinit(gpa);

    try node.props.put("class", try gpa.dupe(u8, "text-danger"));
    try node.props.put("other", try gpa.dupe(u8, "another-property"));

    const result = try node.toHtml(gpa);
    defer gpa.free(result);
    try std.testing.expectEqualStrings("<h1 class=\"text-danger\" other=\"another-property\">Hello, world!</h1>", result);
}

test "test void leaf node with value should error" {
    const gpa = std.testing.allocator;
    var node = try LeafNode.init(gpa, "img", "Hello, world!", true);
    defer node.deinit(gpa);

    const result = node.toHtml(gpa);
    try std.testing.expectError(NodeError.VoidElementHasContent, result);
}
