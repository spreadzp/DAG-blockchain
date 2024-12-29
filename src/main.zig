const std = @import("std");
const dag = @import("blockchain/dag.zig");
const storage = @import("storage/sylladb.zig");
const cli = @import("cli.zig");
const server = @import("server/server.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var blockchain = try dag.DAGBlockchain.init(allocator);
    defer blockchain.deinit();
    std.debug.print("Initializing DAG Blockchain CLI...\n", .{});
    try server.start();
    var cli_app = cli.CLI.init(allocator, blockchain);
    try cli_app.start();
}
