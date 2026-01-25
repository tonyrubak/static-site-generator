const std = @import("std");

pub const LeafNode = struct {
    tag: []const u8,
    value: []const u8,
    props: std.StringHashMap([]const u8),

    pub fn init(
        allocator: std.mem.Allocator,
        tag: []const u8,
        value: []const u8,
    ) !LeafNode {
        const self = LeafNode{
            .tag = tag,
            .value = value,
            .props = std.StringHashMap([]const u8).init(allocator),
        };

        return self;
    }

    pub fn deinit(self: *LeafNode) void {
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
    var node = try LeafNode.init(gpa, "p", "Hello, world!");
    defer node.deinit();

    const result = try node.toHtml(gpa);
    defer gpa.free(result);
    try std.testing.expectEqualStrings("<p>Hello, world!</p>", result);
}

test "test leaf node with 1 property" {
    const gpa = std.testing.allocator;
    var node = try LeafNode.init(gpa, "h1", "Hello, world!");
    defer node.deinit();

    try node.props.put("class", "text-danger");

    const result = try node.toHtml(gpa);
    defer gpa.free(result);
    try std.testing.expectEqualStrings("<h1 class=\"text-danger\">Hello, world!</h1>", result);
}

test "test leaf node with 2 properties" {
    const gpa = std.testing.allocator;
    var node = try LeafNode.init(gpa, "h1", "Hello, world!");
    defer node.deinit();

    try node.props.put("class", "text-danger");
    try node.props.put("other", "another-property");

    const result = try node.toHtml(gpa);
    defer gpa.free(result);
    try std.testing.expectEqualStrings("<h1 class=\"text-danger\" other=\"another-property\">Hello, world!</h1>", result);
}
