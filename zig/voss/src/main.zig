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

const C = struct {
    buf: [256]u8 = undefined,
    k: usize = 0,
    allocator: std.mem.Allocator,
    map: *std.StringHashMap(u32),

    pub fn init(allocator: std.mem.Allocator, map: *std.StringHashMap(u32)) C {
        return .{
            .allocator = allocator,
            .map = map,
        };
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
                result.key_ptr.* = try self.allocator.dupe(u8, word);
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

    var map = std.StringHashMap(u32).init(allocator);

    var collector = C.init(allocator, &map);

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
    var entries = try std.ArrayList(Entry).initCapacity(allocator, map.count());
    defer entries.deinit(allocator);
    var it = map.iterator();
    while (it.next()) |e| entries.appendAssumeCapacity(.{ .key = e.key_ptr.*, .count = e.value_ptr.* });
    std.mem.sort(Entry, entries.items, {}, struct {
        fn f(_: void, l: Entry, r: Entry) bool {
            return l.count > r.count;
        }
    }.f);
    for (entries.items[0..@min(k, entries.items.len)]) |e| {
        try stdout.print("{s} - {d}\n", .{ e.key, e.count });
    }

    try stdout.flush();
}
