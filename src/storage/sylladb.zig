// src/storage/sylladb.zig
const std = @import("std");
const dag = @import("../blockchain/dag.zig");

pub const SyllaDB = struct {
    allocator: std.mem.Allocator,
    nodes: std.AutoHashMap([32]u8, dag.DAGNode),

    pub fn init(allocator: std.mem.Allocator) !*SyllaDB {
        const self = try allocator.create(SyllaDB);
        self.* = .{
            .allocator = allocator,
            .nodes = std.AutoHashMap([32]u8, dag.DAGNode).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *SyllaDB) void {
        self.nodes.deinit();
        self.allocator.destroy(self);
    }

    pub fn isEmpty(self: *SyllaDB) !bool {
        return self.nodes.count() == 0;
    }

    pub fn store(self: *SyllaDB, id: *const [32]u8, node: dag.DAGNode) !void {
        try self.nodes.put(id.*, node);
    }

    pub fn get(self: *SyllaDB, id: [32]u8) !dag.DAGNode {
        if (self.nodes.get(id)) |node| {
            return node;
        }
        return error.NodeNotFound;
    }

    pub fn getApprovers(self: *SyllaDB, id: [32]u8) ![]dag.DAGNode {
        _ = self;
        _ = id;
        // Mock implementation: return empty array
        return &[_]dag.DAGNode{};
    }

    pub const Iterator = struct {
        db: *SyllaDB,
        inner: std.AutoHashMap([32]u8, dag.DAGNode).Iterator,

        pub fn next(self: *Iterator) !?dag.DAGNode {
            if (self.inner.next()) |entry| {
                return entry.value_ptr.*;
            }
            return null;
        }
    };

    pub fn iterator(self: *SyllaDB) !Iterator {
        return Iterator{
            .db = self,
            .inner = self.nodes.iterator(),
        };
    }
};
