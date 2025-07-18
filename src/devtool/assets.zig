// This file is auto-generated. Do not edit manually.
const std = @import("std");

const Self = @This();

path: []const u8,
content: []const u8,
mime_type: []const u8,
response: [:0]const u8,

pub fn init(
    comptime path: []const u8,
    comptime content: []const u8,
    comptime mime_type: []const u8,
) Self {
    var buf: [20]u8 = undefined;
    const n = std.fmt.bufPrint(&buf, "{d}", .{content.len}) catch unreachable;
    const content_length = buf[0..n.len];
    const response = "HTTP/1.1 200 OK\n" ++
        "Content-Type: " ++ mime_type ++ "\n" ++
        "Content-Length: " ++ content_length ++ "\n" ++
        "\n" ++
        content;
    return Self{
        .path = path,
        .content = content,
        .mime_type = mime_type,
        .response = response,
    };
}

pub const not_found_asset = Self.init(
    "/notfound.html",
    "<div>Page not found</div>",
    "text/html",
);

pub const assets = [_]Self{
    Self.init(
        "/index.html",
        @embedFile("dist/index.html"),
        "text/html",
    ),
    Self.init(
        "/vite.svg",
        @embedFile("dist/vite.svg"),
        "image/svg+xml",
    ),
    Self.init(
        "/assets/index-_UQWOD7Y.css",
        @embedFile("dist/assets/index-_UQWOD7Y.css"),
        "text/css",
    ),
    Self.init(
        "/assets/index-B7X5OICm.js",
        @embedFile("dist/assets/index-B7X5OICm.js"),
        "application/javascript",
    ),
    Self.init(
        "/tauri.svg",
        @embedFile("dist/tauri.svg"),
        "image/svg+xml",
    ),
};

pub fn get_asset(path: []const u8) Self {
    for (assets) |asset| {
        if (std.mem.eql(u8, asset.path, path)) {
            return asset;
        }
    }
    return not_found_asset;
}
