const std = @import("std");
const builtin = @import("builtin");
const zlog = @import("zlog");
const tanuki = @import("tanuki");
const multitool = @import("multitool");

const routes = @import("routes.zig");
const middleware = @import("middleware.zig");
const config = @import("config.zig");
const utils = @import("utils.zig");
const server = @import("server.zig");
const Server = server.Server;

pub var server_inst: *tanuki.Server(Server) = undefined;

fn shutdown() void {
    server_inst.stop();
}

pub fn main() !void {
    try multitool.setAbortSignalHandler(shutdown);

    var allocator: std.mem.Allocator = undefined;
    if (builtin.mode == .Debug) {
        var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
        allocator = gpa.allocator();
    } else {
        allocator = std.heap.page_allocator;
    }

    try zlog.initGlogDefault(allocator);
    defer zlog.deinitGlobalLogger();

    var cfg = try config.loadConfig(allocator);
    defer cfg.deinit(allocator);

    const host = "0.0.0.0";
    const port = 5882;
    var appserver: Server = Server.init(
        allocator,
        &cfg,
        host,
        port,
    );
    defer appserver.deinit();

    var webserver = try tanuki.Server(Server).init(
        allocator,
        &appserver,
        .{
            .address = host,
            .port = port,
        },
    );
    server_inst = &webserver;
    try webserver.addMiddleware(allocator, middleware.Logger, .{});

    try appserver.preloadDirectoryRecursive("web/dist");
    try webserver.router.get("/", routes.index);
    try webserver.router.get("/assets/:file", routes.assets);
    try webserver.router.get("/callback", routes.callback);
    try webserver.router.get("/login", routes.login);
    try webserver.router.get("/logout", routes.logout);
    try webserver.router.get("/isLoggedIn", routes.isLoggedIn);
    try webserver.router.get("/user", routes.getUserData);
    try webserver.router.get("/playlists", routes.getPlaylists);
    try webserver.router.get("/queue-playlist/:id", routes.queuePlaylist);

    zlog.info("Starting webserver on http://{s}:{d}", .{ host, port });
    try webserver.start();
    std.debug.print("\n", .{});
    zlog.info("Server stopped", .{});
}
