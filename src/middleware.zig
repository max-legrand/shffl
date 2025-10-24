const std = @import("std");
const tanuki = @import("tanuki");
const zlog = @import("zlog");
const utils = @import("utils.zig");
const server = @import("server.zig");
const Server = server.Server;
const ArrayList = std.ArrayList;

pub const Logger = struct {
    pub const Config = struct {};

    pub fn init(_: Config, _: anytype) !Logger {
        return .{};
    }

    pub fn execute(_: *const Logger, req: *tanuki.Request, res: *tanuki.Response, executor: anytype) !void {
        const start = std.time.milliTimestamp();
        executor.next() catch |err| {
            const end = std.time.milliTimestamp();
            zlog.err("[{s}] {s} {d}ms - {s}", .{ @tagName(req.req.head.method), req.req.head.target, end - start, @errorName(err) });
            return err;
        };
        const end = std.time.milliTimestamp();
        zlog.info("[{s}] {s} {d}ms - {d}", .{ @tagName(req.req.head.method), req.req.head.target, end - start, res.status });
    }
};
