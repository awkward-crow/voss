const std = @import("std");
const voss = @import("voss");

pub fn main() !void {
    const s = "_EAt my $hortZ..";
    const n = 16;
    var t: @Vector(n, u8) = s.*;
    std.debug.print("{s}\n", .{@as([n]u8, t)});

    const A: @Vector(n, u8) = @splat(@as(u8, 'A'));
    const Z: @Vector(n, u8) = @splat(@as(u8, 'Z'));

    const upper = (A <= t) & (t <= Z);
    std.debug.print("{any}\n", .{@as([n]bool, upper)});

    const d: @Vector(n, u8) = @splat(@as(u8, 0x20));
    const zero: @Vector(n, u8) = @splat(@as(u8, 0));

    t |= @select(u8, upper, d, zero);
    std.debug.print("{s}\n", .{@as([n]u8, t)});
    std.debug.print("{s}\n", .{s});

    //     const u = t | @select(u8, upper, d, zero);
    //
    //     std.debug.print("{s}\n", .{@as([n]u8, u)});
    //
    //     const a: @Vector(n, u8) = @splat(@as(u8, 'a'));
    //     const z: @Vector(n, u8) = @splat(@as(u8, 'z'));
    //
    //     const alpha = (a <= u) & (u <= z);
    //     std.debug.print("{any}\n", .{@as([n]bool, alpha)});
    //
    //     const indices = std.simd.iota(u8, n);
    //     const nulls: @Vector(n, u8) = @splat(@as(u8, n));
    //
    //     const p = @reduce(.Min, @select(u8, alpha, indices, nulls));
    //     std.debug.print("{d}\n", .{p});
    //
    //     const mask: @Vector(n, u8) = @splat(@as(u8, p));
    //     std.debug.print("{any}\n", .{@as([n]u8, mask)});
    //
    //     const rho = @select(u8, (~alpha) & (mask < indices), indices, nulls);
    //     const q = @reduce(.Min, rho);
    //     std.debug.print("{any}\n", .{@as([n]u8, rho)});
    //     std.debug.print("{d}\n", .{q});
    //
    //     std.debug.print("{s}\n", .{s[p..q]});
    //     std.debug.print("{s}\n", .{@as([n]u8, u)[p..q]});

    std.debug.print("ok\n", .{});
}
