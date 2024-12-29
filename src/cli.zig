const std = @import("std");
const dag = @import("blockchain/dag.zig");

const Command = enum {
    send,
    balance,
    tx,
    list,
    help,
    exit,
};

pub const CLI = struct {
    allocator: std.mem.Allocator,
    blockchain: *dag.DAGBlockchain,
    running: bool,

    pub fn init(allocator: std.mem.Allocator, blockchain: *dag.DAGBlockchain) CLI {
        return .{
            .allocator = allocator,
            .blockchain = blockchain,
            .running = false,
        };
    }

    pub fn start(self: *CLI) !void {
        self.running = true;
        const stdin = std.io.getStdIn().reader();
        var buffer: [1024]u8 = undefined;

        try self.printHelp();

        while (self.running) {
            std.debug.print("\n> ", .{});
            if (try stdin.readUntilDelimiterOrEof(&buffer, '\n')) |user_input| {
                const trimmed = std.mem.trim(u8, user_input, " \t\r\n");
                try self.handleCommand(trimmed);
            }
        }
    }

    fn handleCommand(self: *CLI, input: []const u8) !void {
        var it = std.mem.split(u8, input, " ");
        const cmd_str = it.first();

        const cmd = std.meta.stringToEnum(Command, cmd_str) orelse {
            std.debug.print("Unknown command: {s}\n", .{cmd_str});
            try self.printHelp();
            return;
        };

        switch (cmd) {
            .send => try self.handleSend(it.rest()),
            .balance => try self.handleBalance(it.rest()),
            .tx => try self.handleGetTx(it.rest()),
            .list => try self.handleList(),
            .help => try self.printHelp(),
            .exit => self.running = false,
        }
    }

    fn handleSend(self: *CLI, args: []const u8) !void {
        var it = std.mem.split(u8, args, " ");
        const sender_hex = it.next() orelse {
            std.debug.print("Error: Missing sender address\n", .{});
            return;
        };
        const receiver_hex = it.next() orelse {
            std.debug.print("Error: Missing receiver address\n", .{});
            return;
        };
        const amount_str = it.next() orelse {
            std.debug.print("Error: Missing amount\n", .{});
            return;
        };

        var sender: [32]u8 = undefined;
        var receiver: [32]u8 = undefined;
        _ = try std.fmt.hexToBytes(&sender, sender_hex);
        _ = try std.fmt.hexToBytes(&receiver, receiver_hex);
        const amount = try std.fmt.parseInt(u64, amount_str, 10);

        var transaction = dag.Transaction{
            .id = undefined,
            .sender = sender,
            .receiver = receiver,
            .amount = amount,
            .timestamp = std.time.milliTimestamp(),
            .signature = undefined,
            .references = undefined,
            .nonce = 0,
        };

        // Generate random ID and signature for demo
        std.crypto.random.bytes(&transaction.id);
        std.crypto.random.bytes(&transaction.signature);

        try self.blockchain.addTransaction(transaction);
        std.debug.print("Transaction sent successfully!\n", .{});
        std.debug.print("Transaction ID: {x}\n", .{std.fmt.fmtSliceHexLower(&transaction.id)});
    }

    fn handleBalance(self: *CLI, args: []const u8) !void {
        var it = std.mem.split(u8, args, " ");
        const address_hex = it.next() orelse {
            std.debug.print("Error: Missing address\n", .{});
            return;
        };

        var address: [32]u8 = undefined;
        _ = try std.fmt.hexToBytes(&address, address_hex);

        const balance = try self.blockchain.ledger.getBalance(address);
        std.debug.print("Balance for {s}: {d}\n", .{ address_hex, balance });
    }

    fn handleGetTx(self: *CLI, args: []const u8) !void {
        var it = std.mem.split(u8, args, " ");
        const tx_id_hex = it.next() orelse {
            std.debug.print("Error: Missing transaction ID\n", .{});
            return;
        };

        var tx_id: [32]u8 = undefined;
        _ = try std.fmt.hexToBytes(&tx_id, tx_id_hex);

        const node = try self.blockchain.db.get(tx_id);
        const tx = node.transaction;

        std.debug.print("\nTransaction Details:\n", .{});
        std.debug.print("ID: {x}\n", .{std.fmt.fmtSliceHexLower(&tx.id)});
        std.debug.print("Sender: {x}\n", .{std.fmt.fmtSliceHexLower(&tx.sender)});
        std.debug.print("Receiver: {x}\n", .{std.fmt.fmtSliceHexLower(&tx.receiver)});
        std.debug.print("Amount: {d}\n", .{tx.amount});
        std.debug.print("Timestamp: {d}\n", .{tx.timestamp});
        std.debug.print("Status: {s}\n", .{if (node.is_confirmed) "Confirmed" else "Pending"});
        if (node.is_confirmed) {
            std.debug.print("Confirmation Time: {d}\n", .{node.confirmation_time.?});
        }
        std.debug.print("Weight: {d:.2}\n", .{node.weight});
    }

    fn handleList(self: *CLI) !void {
        var it = self.blockchain.db.nodes.iterator();
        var confirmed: usize = 0;
        var pending: usize = 0;

        std.debug.print("\nTransaction List:\n", .{});
        while (it.next()) |entry| {
            const node = entry.value_ptr;
            const tx = node.transaction;
            std.debug.print("TX {x}: {s} | Amount: {d} | Weight: {d:.2}\n", .{
                std.fmt.fmtSliceHexLower(&tx.id),
                if (node.is_confirmed) "Confirmed" else "Pending",
                tx.amount,
                node.weight,
            });

            if (node.is_confirmed) {
                confirmed += 1;
            } else {
                pending += 1;
            }
        }

        std.debug.print("\nSummary:\n", .{});
        std.debug.print("Total Transactions: {d}\n", .{confirmed + pending});
        std.debug.print("Confirmed: {d}\n", .{confirmed});
        std.debug.print("Pending: {d}\n", .{pending});
    }

    fn printHelp(self: *CLI) !void {
        _ = self;
        std.debug.print("\nAvailable Commands:\n", .{});
        std.debug.print("  send <sender> <receiver> <amount>  Send tokens\n", .{});
        std.debug.print("  balance <address>                  Get account balance\n", .{});
        std.debug.print("  tx <id>                           Get transaction details\n", .{});
        std.debug.print("  list                              List all transactions\n", .{});
        std.debug.print("  help                              Show this help message\n", .{});
        std.debug.print("  exit                              Exit the CLI\n", .{});
        std.debug.print("\nNote: Addresses and transaction IDs should be in hex format\n", .{});
    }
};
