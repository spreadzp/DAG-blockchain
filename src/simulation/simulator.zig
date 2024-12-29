const std = @import("std");
const dag = @import("../blockchain/dag.zig");

pub const TransactionGenerator = struct {
    rng: std.rand.DefaultPrng,
    blockchain: *dag.DAGBlockchain,

    pub fn init(blockchain: *dag.DAGBlockchain) TransactionGenerator {
        const timestamp: i64 = std.time.milliTimestamp();
        return .{
            .rng = std.rand.DefaultPrng.init(@as(u64, @intCast(timestamp))),
            .blockchain = blockchain,
        };
    }

    pub fn generateTransaction(self: *TransactionGenerator) !dag.Transaction {
        var id: [32]u8 = undefined;
        var sender: [32]u8 = undefined;
        var receiver: [32]u8 = undefined;
        var signature: [64]u8 = undefined;

        // Generate random values for transaction fields
        self.rng.random().bytes(&id);
        self.rng.random().bytes(&sender);
        self.rng.random().bytes(&receiver);
        self.rng.random().bytes(&signature);

        std.debug.print("Generated new transaction:\n", .{});
        std.debug.print("  ID: {x}\n", .{std.fmt.fmtSliceHexLower(&id)});
        std.debug.print("  Sender: {x}\n", .{std.fmt.fmtSliceHexLower(&sender)});
        std.debug.print("  Receiver: {x}\n", .{std.fmt.fmtSliceHexLower(&receiver)});
        std.debug.print("  Amount: {d}\n", .{100}); // Fixed amount for simulation

        return dag.Transaction{
            .id = id,
            .sender = sender,
            .receiver = receiver,
            .amount = 100,
            .timestamp = std.time.milliTimestamp(),
            .signature = signature,
            .references = undefined,
            .nonce = self.rng.random().int(u64),
        };
    }
};

pub const SimulationStats = struct {
    start_time: i64,
    total_transactions: u64,
    confirmed_transactions: u64,

    pub fn init() SimulationStats {
        return .{
            .start_time = std.time.milliTimestamp(),
            .total_transactions = 0,
            .confirmed_transactions = 0,
        };
    }

    pub fn updateStats(self: *SimulationStats, processed: u32) void {
        self.total_transactions += processed;
    }

    pub fn printStats(self: *SimulationStats) void {
        const duration_ms = std.time.milliTimestamp() - self.start_time;
        const duration_s = @as(f64, @floatFromInt(duration_ms)) / 1000.0;
        const total_txs = @as(f64, @floatFromInt(self.total_transactions));
        const tps = @as(u64, @intFromFloat(total_txs / duration_s));

        std.debug.print(
            \\Simulation Results:
            \\Total Transactions: {}
            \\Duration: {d:.2} seconds
            \\Average TPS: {}
            \\
        , .{
            self.total_transactions,
            duration_s,
            tps,
        });
    }
};

pub const NetworkSimulator = struct {
    generator: TransactionGenerator,
    tps_target: u32,
    running: bool,
    stats: SimulationStats,

    pub fn init(blockchain: *dag.DAGBlockchain, tps: u32) NetworkSimulator {
        return .{
            .generator = TransactionGenerator.init(blockchain),
            .tps_target = tps,
            .running = false,
            .stats = SimulationStats.init(),
        };
    }

    pub fn start(self: *NetworkSimulator, duration_ms: u64) !void {
        self.running = true;
        const timestamp: i64 = std.time.milliTimestamp();
        const start_time = if (timestamp >= 0) @as(u64, @intCast(timestamp)) else 0;
        const end_time = start_time + duration_ms;

        std.debug.print("Starting simulation with {d} TPS target...\n", .{self.tps_target});
        std.debug.print("Simulation will run for {d} ms\n", .{duration_ms});

        var total_transactions: u32 = 0;
        var consensus_rounds: u32 = 0;

        while (self.running and (if (std.time.milliTimestamp() >= 0) @as(u64, @intCast(std.time.milliTimestamp())) else 0) < end_time) {
            const batch_size = self.tps_target / 10;
            try self.processBatch(batch_size);
            total_transactions += batch_size;

            try self.generator.blockchain.runConsensus();
            consensus_rounds += 1;
            self.stats.updateStats(batch_size);

            if (consensus_rounds % 10 == 0) {
                std.debug.print("Progress: {d} transactions processed, {d} consensus rounds completed\n", .{total_transactions, consensus_rounds});
            }

            std.time.sleep(100 * std.time.ns_per_ms);
        }

        std.debug.print("\nSimulation completed:\n", .{});
        std.debug.print("Total transactions: {d}\n", .{total_transactions});
        std.debug.print("Consensus rounds: {d}\n", .{consensus_rounds});
        std.debug.print("Average TPS: {d:.2}\n", .{@as(f32, @floatFromInt(total_transactions)) * 1000.0 / @as(f32, @floatFromInt(duration_ms))});
    }

    pub fn stop(self: *NetworkSimulator) void {
        self.running = false;
    }

    fn processBatch(self: *NetworkSimulator, size: u32) !void {
        std.debug.print("\nProcessing new batch ({d} transactions)...\n", .{size});
        var i: u32 = 0;
        while (i < size) : (i += 1) {
            const transaction = try self.generator.generateTransaction();
            try self.generator.blockchain.addTransaction(transaction);
        }
    }
};
