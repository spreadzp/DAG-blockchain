const std = @import("std");
const Connection = std.net.Server.Connection;

pub const Method = enum {
    GET,
    POST,
    pub fn init(text: []const u8) !Method {
        return MethodMap.get(text).?;
    }
    pub fn is_supported(m: []const u8) bool {
        const method = MethodMap.get(m);
        if (method) |_| {
            return true;
        }
        return false;
    }
};

const Map = std.static_string_map.StaticStringMap;
const MethodMap = Map(Method).initComptime(.{
    .{ "GET", Method.GET },
    .{ "POST", Method.POST },
});

pub const Request = struct {
    method: Method,
    version: []const u8,
    uri: []const u8,
    body: []const u8,

    pub fn init(method: Method, uri: []const u8, version: []const u8, body: []const u8) Request {
        return Request{
            .method = method,
            .uri = uri,
            .version = version,
            .body = body,
        };
    }
};

pub fn parse_request(text: []u8) Request {
    // Find the end of headers (double newline)
    const headers_end = std.mem.indexOf(u8, text, "\r\n\r\n") orelse text.len;

    // Parse the first line for method, URI, and version
    const first_line_end = std.mem.indexOfScalar(u8, text, '\n') orelse text.len;
    var first_line = std.mem.splitScalar(u8, text[0..first_line_end], ' ');
    const method = Method.init(first_line.next().?) catch unreachable;
    const uri = first_line.next().?;
    const version = first_line.next().?;

    // Extract body if present
    const body = if (headers_end + 4 < text.len)
        text[headers_end + 4 ..]
    else
        "";

    return Request.init(method, uri, version, body);
}

pub fn read_request(conn: Connection, buffer: []u8) !usize {
    const reader = conn.stream.reader();
    const bytes_read = try reader.read(buffer);
    return bytes_read;
}
