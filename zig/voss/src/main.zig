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
