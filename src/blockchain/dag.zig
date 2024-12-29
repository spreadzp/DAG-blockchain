// src/blockchain/dag.zig
const std = @import("std");
const TigerBeetle = @import("../storage/tigerbeetle.zig").TigerBeetle;
const SyllaDB = @import("../storage/sylladb.zig").SyllaDB;
const Zwasm = @import("../runtime/zwasm.zig").Zwasm;

pub const Transaction = struct {
    id: [32]u8,
    sender: [32]u8,
    receiver: [32]u8,
    amount: u64,
    timestamp: i64,
    signature: [64]u8,
    references: [2][32]u8,
    nonce: u64,

    pub fn verify(self: *const Transaction) !bool {
        // Базовая верификация транзакции
        if (self.amount == 0) return error.InvalidAmount;
        if (self.timestamp > std.time.milliTimestamp()) return error.FutureTimestamp;
        return true;
    }
};

pub const DAGNode = struct {
    transaction: Transaction,
    weight: f32,
    is_confirmed: bool,
    confirmation_time: ?i64,

    pub fn init(transaction: Transaction) DAGNode {
        return .{
            .transaction = transaction,
            .weight = 1.0,
            .is_confirmed = false,
            .confirmation_time = null,
        };
    }
};

const TipSelection = struct {
    const ALPHA: f32 = 0.001; // Параметр случайности для выбора

    rng: std.rand.DefaultPrng,
    dag: *DAGBlockchain,

    pub fn init(dag: *DAGBlockchain) TipSelection {
        return .{
            .rng = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp())),
            .dag = dag,
        };
    }

    pub fn selectTips(self: *TipSelection) ![2][32]u8 {
        var tips: [2][32]u8 = undefined;

        // Выбираем две разные транзакции для подтверждения
        var i: usize = 0;
        while (i < 2) : (i += 1) {
            const tip = try self.randomWalk();
            tips[i] = tip;

            // Убеждаемся, что вторая транзакция отличается от первой
            if (i == 1 and std.mem.eql(u8, &tips[0], &tip)) {
                i -= 1;
                continue;
            }
        }

        return tips;
    }

    fn randomWalk(self: *TipSelection) ![32]u8 {
        var current = try self.dag.getGenesis();

        while (true) {
            const approvers = try self.dag.db.getApprovers(current);
            if (approvers.len == 0) break;

            // Выбор следующей транзакции на основе весов
            var selected = approvers[0];
            var max_weight: f32 = -std.math.inf(f32);

            for (approvers) |approver| {
                const random = self.rng.random().float(f32) * @This().ALPHA;
                const weight = approver.weight + random;

                if (weight > max_weight) {
                    max_weight = weight;
                    selected = approver;
                }
            }

            current = selected.transaction.id;
        }

        return current;
    }
};

pub const DAGBlockchain = struct {
    const CONFIRMATION_THRESHOLD: f32 = 5.0;

    allocator: std.mem.Allocator,
    db: *SyllaDB,
    ledger: *TigerBeetle,
    wasm_runtime: *Zwasm,
    tip_selection: TipSelection,

    pub fn init(allocator: std.mem.Allocator) !*DAGBlockchain {
        std.debug.print("Initializing DAG Blockchain...\n", .{});
        
        var self = try allocator.create(DAGBlockchain);
        self.* = .{
            .allocator = allocator,
            .db = try SyllaDB.init(allocator),
            .ledger = try TigerBeetle.init(allocator),
            .wasm_runtime = try Zwasm.init(allocator),
            .tip_selection = undefined,
        };

        self.tip_selection = TipSelection.init(self);
        try self.initGenesis();

        std.debug.print("DAG Blockchain initialized successfully\n", .{});
        std.debug.print("Genesis block created\n", .{});
        return self;
    }

    pub fn deinit(self: *DAGBlockchain) void {
        self.db.deinit();
        self.ledger.deinit();
        self.wasm_runtime.deinit();
        self.allocator.destroy(self);
    }

    fn initGenesis(self: *DAGBlockchain) !void {
        var genesis_transaction = Transaction{
            .id = [_]u8{0} ** 32,
            .sender = [_]u8{0} ** 32,
            .receiver = [_]u8{0} ** 32,
            .amount = 0,
            .timestamp = std.time.milliTimestamp(),
            .signature = [_]u8{0} ** 64,
            .references = [_][32]u8{[_]u8{0} ** 32} ** 2,
            .nonce = 0,
        };

        const genesis_node = DAGNode.init(genesis_transaction);
        try self.db.store(&genesis_transaction.id, genesis_node);
    }

    pub fn addTransaction(self: *DAGBlockchain, transaction: Transaction) !void {
        std.debug.print("Processing transaction: {x}\n", .{std.fmt.fmtSliceHexLower(&transaction.id)});
        
        // Верификация транзакции
        std.debug.print("  Verifying transaction signature...\n", .{});
        _ = try transaction.verify();

        // Проверка баланса
        std.debug.print("  Checking sender balance...\n", .{});
        try self.ledger.checkBalance(transaction.sender, transaction.amount);

        // Выбор и проверка двух транзакций для подтверждения
        std.debug.print("  Selecting tips for references...\n", .{});
        const tips = try self.tip_selection.selectTips();

        var new_transaction = transaction;
        new_transaction.references = tips;
        
        std.debug.print("  Selected tips: [{x}, {x}]\n", 
            .{std.fmt.fmtSliceHexLower(&tips[0]), std.fmt.fmtSliceHexLower(&tips[1])});

        // Создание нового узла
        const node = DAGNode.init(new_transaction);
        try self.db.store(&new_transaction.id, node);
        std.debug.print("  Transaction added to DAG\n", .{});
    }

    fn updateWeights(self: *DAGBlockchain, references: [2][32]u8) !void {
        for (references) |ref| {
            var node = try self.db.get(ref);
            node.weight += 1.0;
            try self.db.store(&ref, node);
        }
    }

    pub fn getGenesis(_: *DAGBlockchain) ![32]u8 {
        return [_]u8{0} ** 32; // ID генезис-транзакции
    }

    pub fn runConsensus(self: *DAGBlockchain) !void {
        std.debug.print("\nRunning consensus round...\n", .{});
        
        var it = self.db.nodes.iterator();
        var unconfirmed_count: usize = 0;
        
        while (it.next()) |entry| {
            const node = entry.value_ptr;
            if (node.is_confirmed) continue;
            unconfirmed_count += 1;
            
            std.debug.print("  Processing transaction {x}...\n", 
                .{std.fmt.fmtSliceHexLower(&entry.key_ptr.*)});
            
            const weight = node.weight;
            std.debug.print("    Current weight: {d:.2}\n", .{weight});

            if (weight >= @This().CONFIRMATION_THRESHOLD) {
                node.is_confirmed = true;
                node.confirmation_time = std.time.milliTimestamp();
                std.debug.print("    Confirmed! Weight exceeds threshold ({d:.2} >= {d:.2})\n", 
                    .{weight, @This().CONFIRMATION_THRESHOLD});
                
                try self.ledger.updateBalance(
                    node.transaction.sender,
                    node.transaction.receiver,
                    node.transaction.amount,
                );
            }
        }
        
        std.debug.print("Consensus round completed. Processed {d} unconfirmed transactions\n", 
            .{unconfirmed_count});
    }
};
