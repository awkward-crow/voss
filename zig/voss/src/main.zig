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

    const s = "_EAt my $hortZ.. at *THE* breakfasT bar!";
    try stdout.print("s is {s}\n", .{s});

    var i: usize = 0;
    var t: @Vector(n, u8) = s[i..][0..n].*;
    var upper = (A <= t) & (t <= Z);
    t |= @select(u8, upper, d, zero);
    var alpha = (a <= t) & (t <= z);
    var p: u8 = 0;
    var q: u8 = 0;

    outer: while (true) {
        var finding_p = true;
        while (finding_p) {
            const q_v: @Vector(n, u8) = @splat(@as(u8, q));
            p = @reduce(.Min, @select(u8, alpha & (q_v <= indices), indices, nulls));
            if (p < n) {
                finding_p = false;
            }
            if (p == n) {
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
        try stdout.print("p is {d}\n", .{p});

        const p_v: @Vector(n, u8) = @splat(@as(u8, p));
        q = @reduce(.Min, @select(u8, (~alpha) & (p_v < indices), indices, nulls));
        try stdout.print("q is {d}\n", .{q});

        try stdout.print("{s}\n", .{@as([n]u8, t)[p..q]});
    }

    try stdout.print("ok\n", .{});
    try stdout.flush();
}
