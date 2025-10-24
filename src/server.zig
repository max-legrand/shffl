const std = @import("std");
const tanuki = @import("tanuki");
const zlog = @import("zlog");
const config = @import("config.zig");

const CachedFile = struct {
    data: []u8,
    compressed_data: ?[]u8 = null,
    content_type: []const u8,
    last_modified: i128,
};

pub const Server = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    cache: std.StringHashMap(CachedFile),
    rwlock: std.Thread.RwLock = .{},
    cfg: *config.Config,
    host: []const u8,
    port: u16,

    login_uuids: std.StringHashMap(void),
    login_uuids_lock: std.Thread.RwLock = .{},

    pub fn init(allocator: std.mem.Allocator, cfg: *config.Config, host: []const u8, port: u16) Self {
        return .{
            .allocator = allocator,
            .cache = std.StringHashMap(CachedFile).init(allocator),
            .cfg = cfg,
            .host = host,
            .port = port,
            .login_uuids = std.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.cache.deinit();
        self.login_uuids.deinit();
    }

    pub fn preloadFile(self: *Self, path: []const u8) !void {
        // Load the file
        const cwd = std.fs.cwd();
        const file = try cwd.openFile(path, .{});
        defer file.close();

        // Get file size for better allocation
        const stat = try file.stat();
        const file_size = stat.size;

        // Allocate memory and read file
        const data = try self.allocator.alloc(u8, file_size);
        const bytes_read = try file.readAll(data);
        if (bytes_read != file_size) {
            self.allocator.free(data);
            return error.IncompleteRead;
        }
        // Compress the data
        var compressed_data: ?[]u8 = null;
        if (file_size > 1024) {
            compressed_data = tanuki.utils.compressData(self.allocator, data) catch null;
        }
        const content_type = tanuki.utils.getMimeType(path);

        // Create cache entry
        const path_copy = try self.allocator.dupe(u8, path);
        const cached_file = CachedFile{
            .data = data,
            .content_type = content_type,
            .last_modified = stat.mtime,
            .compressed_data = compressed_data,
        };

        // Store in cache
        try self.cache.put(path_copy, cached_file);

        zlog.debug("Preloaded file: {s}", .{path});
    }

    pub fn preloadDirectory(self: *Self, dir_path: []const u8) !void {
        const cwd = std.fs.cwd();
        var dir = try cwd.openDir(dir_path, .{ .iterate = true });
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind != .file) continue;

            const full_path = try std.fs.path.join(
                self.allocator,
                &[_][]const u8{ dir_path, entry.name },
            );
            defer self.allocator.free(full_path);

            const content_type = tanuki.utils.getMimeType(entry.name);
            try self.preloadFile(full_path, content_type);
        }
        zlog.debug("Preloaded directory: {s}", .{dir_path});
    }

    fn preloadDirectoryRecursiveInternal(self: *Self, base_path: []const u8, current_path: []const u8) !void {
        const cwd = std.fs.cwd();
        var dir = try cwd.openDir(current_path, .{ .iterate = true });
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            const full_path = try std.fs.path.join(
                self.allocator,
                &[_][]const u8{ current_path, entry.name },
            );
            defer self.allocator.free(full_path);

            if (entry.kind == .directory) {
                try self.preloadDirectoryRecursiveInternal(
                    base_path,
                    full_path,
                );
            } else if (entry.kind == .file) {
                try self.preloadFile(full_path);
            }
        }
    }

    pub fn preloadDirectoryRecursive(self: *Self, dir_path: []const u8) !void {
        try self.preloadDirectoryRecursiveInternal(dir_path, dir_path);
        zlog.debug("Recursively preloaded directory: {s}", .{dir_path});
    }

    pub fn getOrLoadFile(self: *Self, path: []const u8) !CachedFile {
        self.rwlock.lockShared();

        // Load the file
        const cwd = std.fs.cwd();
        const file = cwd.openFile(path, .{}) catch |err| {
            self.rwlock.unlockShared();
            zlog.err("Error opening file: {s} ({})", .{ path, err });
            return err;
        };
        defer file.close();

        // Get file size for better allocation
        const stat = try file.stat();

        const current_mod_time = stat.mtime;

        // Check if file is already cached and up to date
        if (self.cache.get(path)) |cached| {
            if (cached.last_modified == current_mod_time) {
                // File hasn't changed, use cached version
                defer self.rwlock.unlockShared();
                return cached;
            }
        }
        self.rwlock.unlockShared();

        // Need to modify the cache, upgrade to write lock
        self.rwlock.lock();
        defer self.rwlock.unlock();
        // Check again inside exclusive lock
        if (self.cache.get(path)) |cached| {
            if (cached.last_modified == current_mod_time) {
                return cached;
            }
            // else, remove outdated cache entry
            const old_path = self.cache.fetchRemove(path).?.key;
            self.allocator.free(old_path);
            self.allocator.free(cached.data);
            if (cached.compressed_data) |cd| self.allocator.free(cd);
        }

        try self.preloadFile(path);
        const cached_file = self.cache.get(path).?;

        return cached_file;
    }
};
