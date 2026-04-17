const std = @import("std");

const Driver = @This();

pub const Error = std.mem.Allocator.Error;

pub fn main(d: *Driver, args: std.process.Args.Iterator) !void {}

pub fn parseArgs(d: *Driver, args: std.process.Args.Iterator) !bool {
    while (args.next()) |arg| {}
}

