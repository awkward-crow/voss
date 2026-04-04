const std = @import("std");
const voss = @import("voss");

var stdout_buffer: [1024]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;

const sw_size = 512;

fn swHash(s: []const u8) usize {
    var h: u32 = 2166136261;
    for (s) |c| { h ^= c; h *%= 16777619; }
    return h & (sw_size - 1);
}

const sw_table: [sw_size][]const u8 = blk: {
    @setEvalBranchQuota(1000000);
    var t = [_][]const u8{""} ** sw_size;
    var it = std.mem.splitScalar(u8, @embedFile("stop_words.txt"), ',');
    while (it.next()) |w| {
        const word = std.mem.trim(u8, w, "\r\n");
        var slot = swHash(word);
        while (t[slot].len != 0) slot = (slot + 1) & (sw_size - 1);
        t[slot] = word;
    }
    const letters = "abcdefghijklmnopqrstuvwxyz";
    for (0..26) |i| {
        const word = letters[i .. i + 1];
        var slot = swHash(word);
        while (t[slot].len != 0) slot = (slot + 1) & (sw_size - 1);
        t[slot] = word;
    }
    break :blk t;
};

fn swContains(word: []const u8) bool {
    var slot = swHash(word);
    while (true) {
        const entry = sw_table[slot];
        if (entry.len == 0) return false;
        if (std.mem.eql(u8, entry, word)) return true;
        slot = (slot + 1) & (sw_size - 1);
    }
}

const SwissMap = struct {
    const G = 16;
    const empty: u8 = 0x80;

    ctrl: []u8,          // length = cap + G (sentinel group mirrors ctrl[0..G])
    keys: [][]const u8,
    vals: []u32,
    cap: usize,          // power of 2, >= G
    len: usize,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator, cap: usize) !SwissMap {
        const ctrl = try allocator.alloc(u8, cap + G);
        @memset(ctrl, empty);
        return .{
            .ctrl = ctrl,
            .keys = try allocator.alloc([]const u8, cap),
            .vals = try allocator.alloc(u32, cap),
            .cap = cap,
            .len = 0,
            .allocator = allocator,
        };
    }

    // set ctrl[s] and mirror into sentinel group for wrap-around probes
    fn setCtrl(self: *SwissMap, s: usize, byte: u8) void {
        self.ctrl[s] = byte;
        if (s < G) self.ctrl[self.cap + s] = byte;
    }

    fn grow(self: *SwissMap) !void {
        var new = try SwissMap.init(self.allocator, self.cap * 2);
        for (0..self.cap) |s| {
            if (self.ctrl[s] == empty) continue;
            const h = std.hash.Wyhash.hash(0, self.keys[s]);
            var slot: usize = @as(usize, @truncate(h >> 7)) & (new.cap - 1);
            while (true) {
                const g: @Vector(G, u8) = new.ctrl[slot..][0..G].*;
                const mask: u16 = @bitCast(g == @as(@Vector(G, u8), @splat(empty)));
                if (mask != 0) {
                    const s2 = (slot + @as(usize, @ctz(mask))) & (new.cap - 1);
                    new.setCtrl(s2, @truncate(h));
                    new.keys[s2] = self.keys[s];
                    new.vals[s2] = self.vals[s];
                    new.len += 1;
                    break;
                }
                slot = (slot + G) & (new.cap - 1);
            }
        }
        self.* = new;
    }

    const Result = struct { value_ptr: *u32, found_existing: bool };

    fn getOrPut(self: *SwissMap, key: []const u8) !Result {
        if (self.len * 8 >= self.cap * 7) try self.grow();
        const h = std.hash.Wyhash.hash(0, key);
        const ctrl_byte: u8 = @as(u8, @truncate(h)) & 0x7F;
        var slot: usize = @as(usize, @truncate(h >> 7)) & (self.cap - 1);
        while (true) {
            const g: @Vector(G, u8) = self.ctrl[slot..][0..G].*;
            var hits: u16 = @bitCast(g == @as(@Vector(G, u8), @splat(ctrl_byte)));
            while (hits != 0) {
                const i: usize = @ctz(hits);
                hits &= hits - 1;
                const s = (slot + i) & (self.cap - 1);
                if (std.mem.eql(u8, self.keys[s], key))
                    return .{ .value_ptr = &self.vals[s], .found_existing = true };
            }
            const empty_mask: u16 = @bitCast(g == @as(@Vector(G, u8), @splat(empty)));
            if (empty_mask != 0) {
                const s = (slot + @as(usize, @ctz(empty_mask))) & (self.cap - 1);
                self.setCtrl(s, ctrl_byte);
                self.keys[s] = try self.allocator.dupe(u8, key);
                self.vals[s] = 0;
                self.len += 1;
                return .{ .value_ptr = &self.vals[s], .found_existing = false };
            }
            slot = (slot + G) & (self.cap - 1);
        }
    }

    const Iter = struct {
        map: *const SwissMap,
        pos: usize = 0,

        fn next(it: *Iter) ?struct { key: []const u8, val: u32 } {
            while (it.pos < it.map.cap) {
                const s = it.pos;
                it.pos += 1;
                if (it.map.ctrl[s] != 0x80)
                    return .{ .key = it.map.keys[s], .val = it.map.vals[s] };
            }
            return null;
        }
    };

    fn iter(self: *const SwissMap) Iter {
        return .{ .map = self };
    }
};

const C = struct {
    buf: [256]u8 = undefined,
    k: usize = 0,
    map: *SwissMap,

    pub fn init(map: *SwissMap) C {
        return .{ .map = map };
    }

    pub fn add(self: *C, s: []const u8) !void {
        @memcpy(self.buf[self.k..][0..s.len], s);
        self.k += s.len;
    }

    pub fn put(self: *C, s: []const u8) !void {
        @memcpy(self.buf[self.k..][0..s.len], s);
        const word = self.buf[0 .. self.k + s.len];
        if (!swContains(word)) {
            const result = try self.map.getOrPut(word);
            if (result.found_existing) {
                result.value_ptr.* += 1;
            } else {
                result.value_ptr.* = 1;
            }
        }
        self.k = 0;
    }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var map = try SwissMap.init(allocator, 16384);

    var collector = C.init(&map);

    const n = 32;

    const A: @Vector(n, u8) = @splat(@as(u8, 'A'));
    const Z: @Vector(n, u8) = @splat(@as(u8, 'Z'));
    const d: @Vector(n, u8) = @splat(@as(u8, 0x20));
    const zero: @Vector(n, u8) = @splat(@as(u8, 0));
    const a: @Vector(n, u8) = @splat(@as(u8, 'a'));
    const z: @Vector(n, u8) = @splat(@as(u8, 'z'));
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len < 2) return error.MissingArgument;
    const input_file = try std.fs.cwd().openFile(args[1], .{});
    defer input_file.close();
    const input_stat = try input_file.stat();
    const s = try input_file.readToEndAlloc(allocator, input_stat.size);
    defer allocator.free(s);

    var i: usize = 0;
    var prev_bit: u32 = 0;

    while (i + n <= s.len) : (i += n) {
        var t: @Vector(n, u8) = s[i..][0..n].*;
        const upper = (A <= t) & (t <= Z);
        t |= @select(u8, upper, d, zero);
        const alpha = (a <= t) & (t <= z);
        const mask: u32 = @bitCast(alpha);
        const shifted = (mask << 1) | prev_bit;
        var starts = mask & ~shifted;
        var ends   = ~mask & shifted;
        const tb: [n]u8 = t;  // lowercased bytes

        // if mid-word from previous chunk, finalize or extend
        if (prev_bit == 1) {
            if (ends != 0) {
                const q: usize = @ctz(ends);
                ends &= ends - 1;
                try collector.put(tb[0..q]);
            } else {
                try collector.add(tb[0..n]);
            }
        }

        // process remaining words in this chunk
        while (starts != 0) {
            const p: usize = @ctz(starts);
            starts &= starts - 1;
            if (ends != 0) {
                const q: usize = @ctz(ends);
                ends &= ends - 1;
                try collector.put(tb[p..q]);
            } else {
                try collector.add(tb[p..n]);
            }
        }

        prev_bit = (mask >> 31) & 1;
    }

    const k = 25;
    const Entry = struct { key: []const u8, count: u32 };

    // min-heap of k entries ordered by count ascending — the root is the
    // smallest of the k largest seen so far and gets evicted on a new arrival
    var heap = std.PriorityQueue(Entry, void, struct {
        fn order(_: void, l: Entry, r: Entry) std.math.Order {
            return std.math.order(l.count, r.count);
        }
    }.order).init(allocator, {});
    defer heap.deinit();

    var it = map.iter();
    while (it.next()) |e| {
        const entry = Entry{ .key = e.key, .count = e.val };
        if (heap.count() < k) {
            try heap.add(entry);
        } else if (entry.count > heap.peek().?.count) {
            _ = heap.remove();
            try heap.add(entry);
        }
    }

    // drain ascending, then reverse to get descending order for display
    var top: [k]Entry = undefined;
    var top_n: usize = 0;
    while (heap.removeOrNull()) |e| : (top_n += 1) top[top_n] = e;
    std.mem.reverse(Entry, top[0..top_n]);
    for (top[0..top_n]) |e| {
        try stdout.print("{s} - {d}\n", .{ e.key, e.count });
    }

    try stdout.flush();
}
