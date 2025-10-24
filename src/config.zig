const std = @import("std");

pub const Config = struct {
    client_id: []const u8,
    client_secret: []const u8,
    redirect_uri: []const u8,
    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        allocator.free(self.client_id);
        allocator.free(self.client_secret);
        allocator.free(self.redirect_uri);
    }
};

pub fn loadConfig(allocator: std.mem.Allocator) !Config {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const client_id = env_map.get("CLIENT_ID") orelse return error.MissingClientId;
    const client_secret = env_map.get("CLIENT_SECRET") orelse return error.MissingClientSecret;
    const redirect_uri = env_map.get("REDIRECT_URI") orelse return error.MissingRedirectUri;
    return .{
        .client_id = try allocator.dupe(u8, client_id),
        .client_secret = try allocator.dupe(u8, client_secret),
        .redirect_uri = try allocator.dupe(u8, redirect_uri),
    };
}
