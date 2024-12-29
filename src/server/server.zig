const std = @import("std");
const SocketConf = @import("config.zig");
const Request = @import("request.zig");
const Response = @import("response.zig");
const simulator = @import("../simulation/simulator.zig");
const Method = Request.Method;
const stdout = std.io.getStdOut().writer();
const Connection = std.net.Server.Connection;

const SimulatorState = struct {
    sim: ?*simulator.NetworkSimulator = null,
    mutex: std.Thread.Mutex = .{},
};

var global_state = SimulatorState{};

fn handleSimulatorStart(connection: Connection, json_body: []const u8) !void {
    const ParseContext = struct {
        tps: u32 = 0,
        duration_ms: u64 = 0,
    };

    var parse_ctx = ParseContext{};
    var json_parser = std.json.Parser.init(std.heap.page_allocator, false);
    defer json_parser.deinit();

    var tree = try json_parser.parse(json_body);
    defer tree.deinit();

    const root = tree.root.Object;
    if (root.get("tps")) |tps_value| {
        parse_ctx.tps = @intCast(tps_value.Integer);
    }
    if (root.get("duration_ms")) |duration_value| {
        parse_ctx.duration_ms = @intCast(duration_value.Integer);
    }

    global_state.mutex.lock();
    defer global_state.mutex.unlock();

    if (global_state.sim != null) {
        try Response.sendJSON(connection, .{
            .status = 400,
            .body = "{\"error\": \"Simulator is already running\"}",
        });
        return;
    }

    try Response.sendJSON(connection, .{
        .status = 200,
        .body = "{\"message\": \"Simulation started successfully\"}",
    });
}

fn handleSimulatorStop(connection: Connection) !void {
    global_state.mutex.lock();
    defer global_state.mutex.unlock();

    if (global_state.sim) |sim| {
        sim.stop();
        global_state.sim = null;
        try Response.sendJSON(connection, .{
            .status = 200,
            .body = "{\"message\": \"Simulation stopped successfully\"}",
        });
    } else {
        try Response.sendJSON(connection, .{
            .status = 400,
            .body = "{\"error\": \"No simulation is currently running\"}",
        });
    }
}

fn handleSimulatorStatus(connection: Connection) !void {
    global_state.mutex.lock();
    defer global_state.mutex.unlock();

    var buffer: [512]u8 = undefined;
    const status = if (global_state.sim != null) "running" else "stopped";

    if (global_state.sim) |sim| {
        const json = try std.fmt.bufPrint(&buffer,
            \\{{
            \\  "status": "{s}",
            \\  "stats": {{
            \\    "total_transactions": {d},
            \\    "tps": {d}
            \\  }}
            \\}}
        , .{ status, sim.stats.total_transactions, sim.tps_target });

        try Response.sendJSON(connection, .{
            .status = 200,
            .body = json,
        });
    } else {
        const json = try std.fmt.bufPrint(&buffer,
            \\{{
            \\  "status": "{s}"
            \\}}
        , .{status});

        try Response.sendJSON(connection, .{
            .status = 200,
            .body = json,
        });
    }
}

pub fn start() !void {
    const socket = try SocketConf.Socket.init();
    try stdout.print("Server starting on {any}\n", .{socket._address});
    var server = try socket._address.listen(.{});

    while (true) {
        const connection = try server.accept();
        var buffer: [4096]u8 = undefined;
        @memset(&buffer, 0);

        const bytes_read = try Request.read_request(connection, &buffer);
        const request = Request.parse_request(buffer[0..bytes_read]);

        if (request.method == Method.GET) {
            if (std.mem.eql(u8, request.uri, "/status")) {
                try handleSimulatorStatus(connection);
            } else if (std.mem.eql(u8, request.uri, "/")) {
                try Response.sendJSON(connection, .{
                    .status = 200,
                    .body = "{\"message\": \"DAG Blockchain Simulator API\"}",
                });
            } else {
                try Response.sendJSON(connection, .{
                    .status = 404,
                    .body = "{\"error\": \"Endpoint not found\"}",
                });
            }
        } else if (request.method == Method.POST) {
            if (std.mem.eql(u8, request.uri, "/start")) {
                try handleSimulatorStart(connection, request.body);
            } else if (std.mem.eql(u8, request.uri, "/stop")) {
                try handleSimulatorStop(connection);
            } else {
                try Response.sendJSON(connection, .{
                    .status = 404,
                    .body = "{\"error\": \"Endpoint not found\"}",
                });
            }
        }
    }
}
