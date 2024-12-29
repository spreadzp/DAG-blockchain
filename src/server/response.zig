const std = @import("std");
const Connection = std.net.Server.Connection;

pub fn send_200(conn: Connection) !void {
    const message = ("HTTP/1.1 200 OK\nContent-Length: 48" ++ "\nContent-Type: text/html\n" ++ "Connection: Closed\n\n<html><body>" ++ "<h1>Hello, World!</h1></body></html>");
    _ = try conn.stream.write(message);
}

pub fn send_404(conn: Connection) !void {
    const message = ("HTTP/1.1 404 Not Found\nContent-Length: 50" ++ "\nContent-Type: text/html\n" ++ "Connection: Closed\n\n<html><body>" ++ "<h1>File not found!</h1></body></html>");
    _ = try conn.stream.write(message);
}

pub const JsonResponse = struct {
    status: u16,
    body: []const u8,
};

pub fn sendJSON(connection: Connection, response: JsonResponse) !void {
    var buffer: [4096]u8 = undefined;

    const headers = try std.fmt.bufPrint(&buffer,
        \\HTTP/1.1 {d} OK
        \\Content-Type: application/json
        \\Content-Length: {d}
        \\Connection: keep-alive
        \\
        \\{s}
    , .{
        response.status,
        response.body.len,
        response.body,
    });

    _ = try connection.stream.write(headers);
}
