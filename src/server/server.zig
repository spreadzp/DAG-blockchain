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

// Log incoming requests
fn logRequest(request: Request.Request) void {
    stdout.print("[REQUEST] {s} {s}\n", .{ @tagName(request.method), request.uri }) catch return;
    if (request.body.len > 0) {
        stdout.print("[REQUEST BODY] {s}\n", .{request.body}) catch return;
    }
}

// Log outgoing responses
fn logResponse(status: u16, body: []const u8) void {
    stdout.print("[RESPONSE] Status: {d}, Body: {s}\n", .{ status, body }) catch return;
}

fn handleSimulatorStart(connection: Connection, request: Request.Request) !void {
    logRequest(request);

    if (request.body.len == 0) {
        const response_body = "{\"error\": \"Missing request body\"}";
        logResponse(400, response_body);
        try Response.sendJSON(connection, .{
            .status = 400,
            .body = response_body,
        });
        return;
    }

    var parse_ctx = struct {
        tps: u32 = 0,
        duration_ms: u64 = 0,
    }{};

    // Parse the JSON request body
    var tree = try std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, request.body, .{});
    defer tree.deinit();

    // Check if the root value is an object
    if (tree.value != .object) {
        const response_body = "{\"error\": \"Invalid JSON: expected an object\"}";
        logResponse(400, response_body);
        try Response.sendJSON(connection, .{
            .status = 400,
            .body = response_body,
        });
        return;
    }

    // Access the root JSON object
    const root = tree.value.object;

    // Extract the 'tps' field
    if (root.get("tps")) |tps_value| {
        if (tps_value != .integer) {
            const response_body = "{\"error\": \"Invalid type for 'tps': expected an integer\"}";
            logResponse(400, response_body);
            try Response.sendJSON(connection, .{
                .status = 400,
                .body = response_body,
            });
            return;
        }
        parse_ctx.tps = @intCast(tps_value.integer);
    } else {
        const response_body = "{\"error\": \"Missing 'tps' parameter\"}";
        logResponse(400, response_body);
        try Response.sendJSON(connection, .{
            .status = 400,
            .body = response_body,
        });
        return;
    }

    // Extract the 'duration_ms' field
    if (root.get("duration_ms")) |duration_value| {
        if (duration_value != .integer) {
            const response_body = "{\"error\": \"Invalid type for 'duration_ms': expected an integer\"}";
            logResponse(400, response_body);
            try Response.sendJSON(connection, .{
                .status = 400,
                .body = response_body,
            });
            return;
        }
        parse_ctx.duration_ms = @intCast(duration_value.integer);
    } else {
        const response_body = "{\"error\": \"Missing 'duration_ms' parameter\"}";
        logResponse(400, response_body);
        try Response.sendJSON(connection, .{
            .status = 400,
            .body = response_body,
        });
        return;
    }
    global_state.mutex.lock();
    defer global_state.mutex.unlock();
    // Start the simulator with the specified duration
    if (global_state.sim) |sim| {
        try sim.start(parse_ctx.duration_ms);
        const response_body = "{\"message\": \"Simulation started successfully\"}";
        logResponse(200, response_body);
        try Response.sendJSON(connection, .{
            .status = 200,
            .body = response_body,
        });
    } else {
        const response_body = "{\"error\": \"No simulator is currently running\"}";
        logResponse(400, response_body);
        try Response.sendJSON(connection, .{
            .status = 400,
            .body = response_body,
        });
    }
}

fn handleSimulatorStop(connection: Connection) !void {
    global_state.mutex.lock();
    defer global_state.mutex.unlock();

    if (global_state.sim) |sim| {
        sim.stop();
        global_state.sim = null;
        const response_body = "{\"message\": \"Simulation stopped successfully\"}";
        logResponse(200, response_body);
        try Response.sendJSON(connection, .{
            .status = 200,
            .body = response_body,
        });
    } else {
        const response_body = "{\"error\": \"No simulation is currently running\"}";
        logResponse(400, response_body);
        try Response.sendJSON(connection, .{
            .status = 400,
            .body = response_body,
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

        logResponse(200, json);
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

        logResponse(200, json);
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

        logRequest(request);

        if (request.method == Method.GET) {
            if (std.mem.eql(u8, request.uri, "/status")) {
                try handleSimulatorStatus(connection);
            } else if (std.mem.eql(u8, request.uri, "/")) {
                const response_body = "{\"message\": \"DAG Blockchain Simulator API\"}";
                logResponse(200, response_body);
                try Response.sendJSON(connection, .{
                    .status = 200,
                    .body = response_body,
                });
            } else {
                const response_body = "{\"error\": \"Endpoint not found\"}";
                logResponse(404, response_body);
                try Response.sendJSON(connection, .{
                    .status = 404,
                    .body = response_body,
                });
            }
        } else if (request.method == Method.POST) {
            if (std.mem.eql(u8, request.uri, "/start")) {
                try handleSimulatorStart(connection, request);
            } else if (std.mem.eql(u8, request.uri, "/stop")) {
                try handleSimulatorStop(connection);
            } else {
                const response_body = "{\"error\": \"Endpoint not found\"}";
                logResponse(404, response_body);
                try Response.sendJSON(connection, .{
                    .status = 404,
                    .body = response_body,
                });
            }
        }
    }
}
