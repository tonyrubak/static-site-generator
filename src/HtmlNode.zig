const std = @import("std");
const Node = @import("Node.zig").Node;

pub const HtmlNode = struct {
    tag: []const u8,
    value: []const u8,
    children: []const Node,
    props: std.StringHashMap([]const u8),

    pub fn init(
        allocator: std.mem.Allocator,
        tag: []const u8,
        value: []const u8,
        children: []const Node,
    ) !HtmlNode {
        const self = HtmlNode{
            .tag = tag,
            .value = value,
            .children = children,
            .props = std.StringHashMap([]const u8).init(allocator),
        };

        return self;
    }

    pub fn deinit(self: *HtmlNode) void {
        self.props.deinit();
    }

    pub fn propsToHtml(
        self: HtmlNode,
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
};

test "test properties to html" {
    const gpa = std.testing.allocator;
    var node = try HtmlNode.init(gpa, "a", "a link", &.{});
    defer node.deinit();
    try node.props.put("href", "https://crimsonhexagon.us");
    const result = try node.propsToHtml(gpa);
    defer gpa.free(result);
    try std.testing.expectEqualStrings(" href=\"https://crimsonhexagon.us\"", result);
}

test "test properties to html with two properties" {
    const gpa = std.testing.allocator;
    var node = try HtmlNode.init(gpa, "a", "a link", &.{});
    defer node.deinit();
    try node.props.put("href", "https://crimsonhexagon.us");
    try node.props.put("other", "another property");
    const result = try node.propsToHtml(gpa);
    defer gpa.free(result);
    try std.testing.expectEqualStrings(" href=\"https://crimsonhexagon.us\" other=\"another property\"", result);
}
