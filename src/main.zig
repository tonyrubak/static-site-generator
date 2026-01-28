const std = @import("std");
const fmt = @import("fmt");
const ssg = @import("ssg");
const TextNode = ssg.TextNode;
const TextType = ssg.TextType;
const HtmlNode = ssg.HtmlNode;
const Node = ssg.Node;
const MarkdownParser = ssg.MarkdownParser;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    try clear_dir("public");
    try copy_tree(allocator, "static", "public");
    var content_dir = try std.fs.cwd().openDir("content/", .{ .iterate = true });
    defer content_dir.close();

    try build_tree(allocator, "content/", "template.html", "public/");
}

fn generate_page(allocator: std.mem.Allocator, src_path: []const u8, template_path: []const u8, dest_path: []const u8) !void {
    std.debug.print("Generating page from {s} to {s} using {s}\n", .{ src_path, dest_path, template_path });
    var wd = try std.fs.cwd().openDir(".", .{});
    defer wd.close();

    const input_file = try wd.openFile(src_path, .{});
    defer input_file.close();

    const length = try input_file.getEndPos();
    var read_buffer: [1024]u8 = undefined;
    var input_f_reader = input_file.reader(&read_buffer);
    var input_reader = &input_f_reader.interface;

    const document = try input_reader.readAlloc(allocator, length);
    defer allocator.free(document);

    const template_file = try wd.openFile(template_path, .{});
    defer template_file.close();

    const template_length = try template_file.getEndPos();
    var template_buffer: [1024]u8 = undefined;
    var template_f_reader = template_file.reader(&template_buffer);
    var template_reader = &template_f_reader.interface;

    const template = try template_reader.readAlloc(allocator, template_length);
    defer allocator.free(template);

    const parser = MarkdownParser{ .document = document };
    var markdown = try parser.parse(allocator);
    defer markdown.deinit(allocator);

    const html = try markdown.toHtml(allocator);
    defer allocator.free(html);

    const title = try parser.extract_title(allocator);
    defer allocator.free(title);

    const title_location = std.mem.indexOf(u8, template, "{{ Title }}") orelse {
        std.debug.print("No title block found in template\n", .{});
        return error.TemplateNoTitle;
    };
    const content_location = std.mem.indexOf(u8, template, "{{ Content }}") orelse {
        std.debug.print("No content block found in template\n", .{});
        return error.TemplateNoContent;
    };

    var output = std.ArrayList(u8).empty;
    defer output.deinit(allocator);
    try output.appendSlice(allocator, template[0..title_location]);
    try output.appendSlice(allocator, title);
    try output.appendSlice(allocator, template[title_location + 11 .. content_location]);
    try output.appendSlice(allocator, html);
    try output.appendSlice(allocator, template[content_location + 13 ..]);

    const output_file_path = std.fs.path.dirname(dest_path);
    if (output_file_path) |path| try wd.makePath(path);

    const output_file = try wd.createFile(dest_path, .{});
    defer output_file.close();
    try output_file.writeAll(output.items);
}

fn clear_dir(path: []const u8) !void {
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch {
        std.debug.print("Destination directory must exist\n", .{});
        return error.InvalidDestination;
    };
    defer dir.close();
    var it = dir.iterate();
    while (try it.next()) |item| {
        try dir.deleteTree(item.name);
    }
}

fn copy_tree(allocator: std.mem.Allocator, in_path: []const u8, out_path: []const u8) !void {
    const cwd = std.fs.cwd();
    var out_dir = cwd.openDir(out_path, .{ .iterate = true }) catch {
        std.debug.print("Destination directory must exist\n", .{});
        return error.InvalidDestination;
    };
    defer out_dir.close();

    var in_dir = cwd.openDir(in_path, .{ .iterate = true }) catch {
        std.debug.print("Source directory must exist\n", .{});
        return error.InvalidSource;
    };
    defer in_dir.close();

    var it = in_dir.iterate();
    while (try it.next()) |item| {
        switch (item.kind) {
            .directory => {
                const src_path = try std.fs.path.join(allocator, &[_][]const u8{ in_path, item.name });
                const dest_path = try std.fs.path.join(allocator, &[_][]const u8{ out_path, item.name });
                defer allocator.free(src_path);
                defer allocator.free(dest_path);
                try out_dir.makeDir(item.name);
                try copy_tree(allocator, src_path, dest_path);
            },
            .file => try std.fs.Dir.copyFile(in_dir, item.name, out_dir, item.name, .{}),
            else => {},
        }
    }
}

fn build_tree(allocator: std.mem.Allocator, in_path: []const u8, template_path: []const u8, out_path: []const u8) !void {
    const cwd = std.fs.cwd();
    var out_dir = cwd.openDir(out_path, .{ .iterate = true }) catch {
        std.debug.print("Destination directory must exist\n", .{});
        return error.InvalidDestination;
    };
    defer out_dir.close();

    var in_dir = cwd.openDir(in_path, .{ .iterate = true }) catch {
        std.debug.print("Source directory must exist\n", .{});
        return error.InvalidSource;
    };
    defer in_dir.close();

    var it = in_dir.iterate();
    while (try it.next()) |item| {
        switch (item.kind) {
            .directory => {
                const src_path = try std.fs.path.join(allocator, &[_][]const u8{ in_path, item.name });
                const dest_path = try std.fs.path.join(allocator, &[_][]const u8{ out_path, item.name });
                defer allocator.free(src_path);
                defer allocator.free(dest_path);
                try out_dir.makeDir(item.name);
                try build_tree(allocator, src_path, template_path, dest_path);
            },
            .file => {
                if (std.mem.eql(u8, std.fs.path.extension(item.name), ".md")) {
                    var buffer: [std.fs.max_path_bytes]u8 = undefined;
                    _ = std.mem.replace(u8, item.name, ".md", ".html", &buffer);
                    const out_name = buffer[0 .. item.name.len + 2];
                    const src_path = try std.fs.path.join(allocator, &[_][]const u8{ in_path, item.name });
                    const dest_path = try std.fs.path.join(allocator, &[_][]const u8{ out_path, out_name });
                    defer allocator.free(src_path);
                    defer allocator.free(dest_path);
                    try generate_page(allocator, src_path, template_path, dest_path);
                }
            },
            else => {},
        }
    }
}
