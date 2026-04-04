

const std = @import("std");
const voss = @import("voss");

var stdout_buffer: [1024]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;

const C = struct {
    buf: [256]u8 = undefined,
    k: usize = 0,
    allocator: std.mem.Allocator,
    map: *std.StringHashMap(u32),
    stop_words: *std.StringHashMap(void),

    pub fn init(allocator: std.mem.Allocator, map: *std.StringHashMap(u32), stop_words: *std.StringHashMap(void)) C {
        return .{
            .allocator = allocator,
            .map = map,
            .stop_words = stop_words,
        };
    }

    pub fn add(self: *C, s: []const u8) !void {
        @memcpy(self.buf[self.k..][0..s.len], s);
        self.k += s.len;
    }

    pub fn put(self: *C, s: []const u8) !void {
        @memcpy(self.buf[self.k..][0..s.len], s);
        const word = self.buf[0 .. self.k + s.len];
        if (!self.stop_words.contains(word)) {
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

    var stop_words = std.StringHashMap(void).init(allocator);
    var sw_it = std.mem.splitScalar(u8, @embedFile("stop_words.txt"), ',');
    while (sw_it.next()) |w| {
        try stop_words.put(std.mem.trim(u8, w, "\n"), {});
    }
    // add single letter characters
    const letters = "abcdefghijklmnopqrstuvwxyz";
    for (letters, 0..) |_, i| {
        try stop_words.put(letters[i .. i + 1], {});
    }

    var map = std.StringHashMap(u32).init(allocator);

    var collector = C.init(allocator, &map, &stop_words);

    const n = 32;

    const A: @Vector(n, u8) = @splat(@as(u8, 'A'));
    const Z: @Vector(n, u8) = @splat(@as(u8, 'Z'));
    const d: @Vector(n, u8) = @splat(@as(u8, 0x20));
    const zero: @Vector(n, u8) = @splat(@as(u8, 0));
    const a: @Vector(n, u8) = @splat(@as(u8, 'a'));
    const z: @Vector(n, u8) = @splat(@as(u8, 'z'));
    const indices = std.simd.iota(u8, n);
    const nulls: @Vector(n, u8) = @splat(@as(u8, n));

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len < 2) return error.MissingArgument;
    const input_file = try std.fs.cwd().openFile(args[1], .{});
    defer input_file.close();
    const input_stat = try input_file.stat();
    const s = try input_file.readToEndAlloc(allocator, input_stat.size);
    defer allocator.free(s);

    var i: usize = 0;
    var t: @Vector(n, u8) = s[i..][0..n].*;
    var upper = (A <= t) & (t <= Z);
    t |= @select(u8, upper, d, zero);
    var alpha = (a <= t) & (t <= z);
    var p: u8 = 0;
    var q: u8 = 0;

    outer: while (true) {
        find_p: while (true) {
            const q_v: @Vector(n, u8) = @splat(@as(u8, q));
            p = @reduce(.Min, @select(u8, alpha & (q_v <= indices), indices, nulls));
            if (p < n) {
                break :find_p;
            } else {
                // p == n i.e. we have hit the end of the vector t
                i += n;
                if (i + n <= s.len) {
                    t = s[i..][0..n].*;
                    upper = (A <= t) & (t <= Z);
                    t |= @select(u8, upper, d, zero);
                    alpha = (a <= t) & (t <= z);
                    q = 0;
                } else {
                    break :outer;
                }
            }
        }

        find_q: while (true) {
            const p_v: @Vector(n, u8) = @splat(@as(u8, p));
            q = @reduce(.Min, @select(u8, (~alpha) & (p_v <= indices), indices, nulls));
            if (q < n) {
                break :find_q;
            } else {
                // q == n i.e. we have hit the end of the vector t
                try collector.add(@as([n]u8, t)[p..q]);
                i += n;
                if (i + n <= s.len) {
                    t = s[i..][0..n].*;
                    upper = (A <= t) & (t <= Z);
                    t |= @select(u8, upper, d, zero);
                    alpha = (a <= t) & (t <= z);
                    p = 0;
                } else {
                    break :outer;
                }
            }
        }

        try collector.put(@as([n]u8, t)[p..q]);
    }

    // try collector.put(s[i..]);
    // try stdout.print("tail is {s}\n", .{s[i..]});

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

const std = @import("std");
const voss = @import("voss");

pub fn main() !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    const n = 16;

    const A: @Vector(n, u8) = @splat(@as(u8, 'A'));
    const Z: @Vector(n, u8) = @splat(@as(u8, 'Z'));
    const d: @Vector(n, u8) = @splat(@as(u8, 0x20));
    const zero: @Vector(n, u8) = @splat(@as(u8, 0));
    const a: @Vector(n, u8) = @splat(@as(u8, 'a'));
    const z: @Vector(n, u8) = @splat(@as(u8, 'z'));
    const indices = std.simd.iota(u8, n);
    const nulls: @Vector(n, u8) = @splat(@as(u8, n));

    const s = "_EAt my $hortZ..";
    try stdout.print("s is {s}\n", .{s});

    var t: @Vector(n, u8) = s.*;
    const upper = (A <= t) & (t <= Z);
    t |= @select(u8, upper, d, zero);
    const alpha = (a <= t) & (t <= z);
    var q: u8 = 0;

    while (true) {
        const q_v: @Vector(n, u8) = @splat(@as(u8, q));
        const p: u8 = @reduce(.Min, @select(u8, alpha & (q_v <= indices), indices, nulls));
        if (p == n) break;
        try stdout.print("p is {d}\n", .{p});

        const p_v: @Vector(n, u8) = @splat(@as(u8, p));
        q = @reduce(.Min, @select(u8, (~alpha) & (p_v < indices), indices, nulls));
        try stdout.print("q is {d}\n", .{q});

        try stdout.print("{s}\n", .{@as([n]u8, t)[p..q]});
    }

    try stdout.print("ok\n", .{});
    try stdout.flush();
}

pub fn main_1() !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    const n = 16;

    const A: @Vector(n, u8) = @splat(@as(u8, 'A'));
    const Z: @Vector(n, u8) = @splat(@as(u8, 'Z'));
    const d: @Vector(n, u8) = @splat(@as(u8, 0x20));
    const zero: @Vector(n, u8) = @splat(@as(u8, 0));
    const a: @Vector(n, u8) = @splat(@as(u8, 'a'));
    const z: @Vector(n, u8) = @splat(@as(u8, 'z'));
    const indices = std.simd.iota(u8, n);
    const nulls: @Vector(n, u8) = @splat(@as(u8, n));

    const s = "_EAt my $hortZ..";
    try stdout.print("s is {s}\n", .{s});

    var t: @Vector(n, u8) = s.*;

    const upper = (A <= t) & (t <= Z);
    t |= @select(u8, upper, d, zero);
    const alpha = (a <= t) & (t <= z);

    var p: u8 = @reduce(.Min, @select(u8, alpha, indices, nulls));
    try stdout.print("p_0 is {d}\n", .{p});

    var p_v: @Vector(n, u8) = @splat(@as(u8, p));
    var rho = @select(u8, (~alpha) & (p_v < indices), indices, nulls);
    var q = @reduce(.Min, rho);
    try stdout.print("q is {d}\n", .{q});

    try stdout.print("{s}\n", .{@as([n]u8, t)[p..q]});

    const q_v: @Vector(n, u8) = @splat(@as(u8, q));
    p = @reduce(.Min, @select(u8, alpha & (q_v <= indices), indices, nulls));
    try stdout.print("p_1 is {d}\n", .{p});

    p_v = @splat(@as(u8, p));
    rho = @select(u8, (~alpha) & (p_v < indices), indices, nulls);
    q = @reduce(.Min, rho);
    try stdout.print("q_1 is {d}\n", .{q});

    try stdout.print("{s}\n", .{@as([n]u8, t)[p..q]});

    try stdout.print("ok\n", .{});
    try stdout.flush();
}

    std.debug.print("{s}\n", .{@as([n]u8, t)});
    std.debug.print("{s}\n", .{s});

