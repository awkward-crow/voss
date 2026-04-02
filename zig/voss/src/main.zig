const std = @import("std");
const voss = @import("voss");

var stdout_buffer: [1024]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;

const C = struct {
    buf: [256]u8 = undefined,
    k: usize = 0,

    pub fn add(self: *C, s: []const u8) !void {
        @memcpy(self.buf[self.k..][0..s.len], s);
        self.k += s.len;
    }

    pub fn put(self: *C, s: []const u8) !void {
        try stdout.print("{s}{s}\n", .{ self.buf[0..self.k], s });
        self.k = 0;
    }
};

pub fn main() !void {
    var collector = C{};
    const n = 16;

    const A: @Vector(n, u8) = @splat(@as(u8, 'A'));
    const Z: @Vector(n, u8) = @splat(@as(u8, 'Z'));
    const d: @Vector(n, u8) = @splat(@as(u8, 0x20));
    const zero: @Vector(n, u8) = @splat(@as(u8, 0));
    const a: @Vector(n, u8) = @splat(@as(u8, 'a'));
    const z: @Vector(n, u8) = @splat(@as(u8, 'z'));
    const indices = std.simd.iota(u8, n);
    const nulls: @Vector(n, u8) = @splat(@as(u8, n));

    const s = "_EAt my $hortZ at *THE* breakfast  T bar bar Bar baR!";
    try stdout.print("{s}\n", .{s});

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

    try stdout.print("\ntail is {s}\n", .{s[i..]});

    try stdout.print("ok\n", .{});
    try stdout.flush();
}
