const std = @import("std");
const multitool = @import("multitool");
const tanuki = @import("tanuki");
const zlog = @import("zlog");
const zul = @import("zul");

const utils = @import("utils.zig");
const Server = @import("server.zig").Server;

fn isAuth(app: *Server, req: *tanuki.Request, res: *tanuki.Response) !bool {
    const token = utils.extractTokenFromCookie(
        &req.headers,
        "AccessToken",
    );
    const refresh_token = utils.extractTokenFromCookie(
        &req.headers,
        "RefreshToken",
    );

    if (refresh_token == null) {
        try res.headers.append(
            res.arena,
            .{
                .name = "Content-Type",
                .value = "application/json",
            },
        );
        try res.write(
            .unauthorized,
            "{\"error\": \"No token found\"}",
        );
        return false;
    }

    if (token == null) {
        const new_token = try utils.refreshAccessToken(
            res.arena,
            refresh_token.?,
            app,
        );
        try res.setCookie(.{
            .name = "AccessToken",
            .value = new_token,
            .max_age = 1800,
            .path = "/",
            .http_only = true,
        });
    }
    return true;
}

pub fn callback_helper(app: *Server, req: *tanuki.Request, res: *tanuki.Response, check_state: bool) !*multitool.Response {
    const code = req.query.get("code");
    if (code == null) return error.ParamsMissing;

    if (check_state) {
        const state = req.query.get("state");
        if (state == null) return error.ParamsMissing;
        const state_value = utils.extractTokenFromCookie(&req.headers, "State");
        if (state_value == null) return error.StateMissing;
        if (!std.mem.eql(u8, state.?, state_value.?)) return error.StateMismatch;
    }

    const request_body = try std.fmt.allocPrint(
        res.arena,
        "grant_type=authorization_code&code={s}&redirect_uri={s}&client_id={s}&client_secret={s}",
        .{
            code.?,
            app.cfg.redirect_uri,
            app.cfg.client_id,
            app.cfg.client_secret,
        },
    );
    var headers = [_]std.http.Header{
        .{
            .name = "Content-Type",
            .value = "application/x-www-form-urlencoded",
        },
    };
    const request_args = multitool.RequestArgs{
        .url = "https://accounts.spotify.com/api/token",
        .method = .POST,
        .headers = headers[0..],
        .body = request_body,
    };
    const result: *multitool.Response = try res.arena.create(multitool.Response);
    try multitool.makeRequest(
        res.arena,
        request_args,
        result,
    );
    return result;
}

pub fn callback(app: *Server, req: *tanuki.Request, res: *tanuki.Response) anyerror!void {
    const result = try callback_helper(app, req, res, true);
    const json_value: std.json.Parsed(std.json.Value) = try std.json.parseFromSlice(
        std.json.Value,
        res.arena,
        result.body.?,
        .{},
    );
    const access_token_value = json_value.value.object.get("access_token");
    if (access_token_value == null) {
        try res.headers.append(
            res.arena,
            .{
                .name = "Location",
                .value = "/",
            },
        );
        try res.write(.see_other, "");
        return;
    }

    const access_token = json_value.value.object.get("access_token").?.string;
    const refresh_token = json_value.value.object.get("refresh_token").?.string;

    try res.setCookie(.{
        .name = "AccessToken",
        .value = access_token,
        .max_age = 1800,
        .path = "/",
        .http_only = true,
    });
    try res.setCookie(.{
        .name = "RefreshToken",
        .value = refresh_token,
        .max_age = 2592000,
        .path = "/",
        .http_only = true,
    });

    try res.headers.append(
        res.arena,
        .{
            .name = "Location",
            .value = "/",
        },
    );
    try res.write(.see_other, "");
}

pub fn assets(app: *Server, req: *tanuki.Request, res: *tanuki.Response) anyerror!void {
    if (req.params == null) return error.ParamsMissing;
    const file = req.params.?.get("file");
    if (file == null) return error.ParamsMissing;

    const path = try std.fmt.allocPrint(
        app.allocator,
        "web/dist/assets/{s}",
        .{file.?},
    );
    try serveFile(app, path, res);
}

pub fn serveFile(app: *Server, path: []const u8, res: *tanuki.Response) !void {
    const file = try app.getOrLoadFile(path);
    if (file.compressed_data) |compressed_data| {
        try res.headers.append(
            res.arena,
            .{
                .name = "Content-Encoding",
                .value = "br",
            },
        );
        try res.headers.append(
            res.arena,
            .{
                .name = "Content-Type",
                .value = file.content_type,
            },
        );
        try res.write(.ok, compressed_data);
        return;
    }
    try res.headers.append(res.arena, .{ .name = "Content-Type", .value = file.content_type });
    try res.write(.ok, file.data);
}

pub fn index(app: *Server, _: *tanuki.Request, res: *tanuki.Response) anyerror!void {
    try serveFile(app, "web/dist/html/index.html", res);
}

pub fn login(app: *Server, _: *tanuki.Request, res: *tanuki.Response) anyerror!void {
    const uuid = zul.UUID.v7();
    const state = try uuid.toHexAlloc(res.arena, .lower);
    const login_url = try std.fmt.allocPrint(
        app.allocator,
        "https://accounts.spotify.com/authorize?client_id={s}&response_type=code&redirect_uri={s}&scope=playlist-read-private%20user-modify-playback-state%20user-read-playback-state&show_dialog=true&state={s}",
        .{ app.cfg.client_id, app.cfg.redirect_uri, state },
    );
    const url_in_arena = try res.arena.dupe(u8, login_url);
    app.allocator.free(login_url);
    try res.headers.append(
        res.arena,
        .{
            .name = "Location",
            .value = url_in_arena,
        },
    );
    try res.setCookie(.{
        .name = "State",
        .value = state,
        .max_age = 2592000,
        .path = "/",
        .http_only = true,
    });
    try res.write(.temporary_redirect, "");
}

pub fn isLoggedIn(_: *Server, req: *tanuki.Request, res: *tanuki.Response) anyerror!void {
    const headers = req.headers;

    const isLoggedInResponse = struct {
        isLoggedIn: bool,
    };
    var result: isLoggedInResponse = .{
        .isLoggedIn = false,
    };
    for (headers.items) |header| {
        if (std.mem.eql(u8, header.name, "Cookie")) {
            const cookie = header.value;
            if (std.mem.startsWith(u8, cookie, "AccessToken=")) {
                result.isLoggedIn = true;
                break;
            } else if (std.mem.startsWith(u8, cookie, "RefreshToken=")) {
                result.isLoggedIn = true;
                break;
            }
        }
    }
    const json_string = try std.json.Stringify.valueAlloc(
        res.arena,
        result,
        .{},
    );
    try res.headers.append(res.arena, .{
        .name = "Content-Type",
        .value = "application/json",
    });
    try res.write(.ok, json_string);
}

pub fn getUserData(app: *Server, req: *tanuki.Request, res: *tanuki.Response) anyerror!void {
    if (try isAuth(app, req, res) == false) {
        try res.write(
            .unauthorized,
            "{\"error\": \"No token found\"}",
        );
        return;
    }
    const token = utils.getToken(req, res);
    if (token == null) {
        return error.NoToken;
    }

    const result = utils.spotifyRequest(
        res.arena,
        "https://api.spotify.com/v1/me",
        req,
        res,
    ) catch |err| {
        switch (err) {
            error.Unauthorized => {
                try logout_helper(res);
                return;
            },
            else => return err,
        }
    };

    zlog.info("Result - {s}", .{result});

    try res.headers.append(
        res.arena,
        .{
            .name = "Content-Type",
            .value = "application/json",
        },
    );
    try res.write(.ok, result);
}

pub fn getPlaylists(app: *Server, req: *tanuki.Request, res: *tanuki.Response) anyerror!void {
    const authenticated = try isAuth(app, req, res);
    if (!authenticated) {
        try res.headers.append(
            res.arena,
            .{
                .name = "Content-Type",
                .value = "application/json",
            },
        );
        try res.write(.unauthorized, "{\"error\": \"No token found\"}");
        return error.Unauthorized;
    }
    const token = utils.getToken(req, res);
    if (token == null) {
        return error.NoToken;
    }

    var offset: u32 = 0;
    var limit: u32 = 50;

    if (req.query.get("offset")) |offset_str| {
        offset = std.fmt.parseInt(u32, offset_str, 10) catch 0;
    }
    if (req.query.get("limit")) |limit_str| {
        limit = std.fmt.parseInt(u32, limit_str, 10) catch 50;
    }

    const url = try std.fmt.allocPrint(
        res.arena,
        "https://api.spotify.com/v1/me/playlists?offset={d}&limit={d}",
        .{ offset, limit },
    );

    const result = try utils.spotifyRequest(res.arena, url, req, res);
    try res.headers.append(
        res.arena,
        .{
            .name = "Content-Type",
            .value = "application/json",
        },
    );
    try res.write(.ok, result);
}

const State = struct {
    uris: [][]const u8,
    allocator: std.mem.Allocator,
    token: []const u8,

    const QueueProgress = struct {
        current: usize,
        total: usize,
    };
    fn handle(state: State, writer: *tanuki.StreamWriter) !void {
        const devices_response = try state.allocator.create(multitool.Response);
        try multitool.makeRequest(state.allocator, multitool.RequestArgs{
            .url = "https://api.spotify.com/v1/me/player/devices",
            .method = .GET,
            .headers = &[_]std.http.Header{
                .{
                    .name = "Authorization",
                    .value = try std.fmt.allocPrint(
                        state.allocator,
                        "Bearer {s}",
                        .{state.token},
                    ),
                },
            },
            .body = null,
        }, devices_response);
        if (devices_response.body == null) {
            return error.NoDevices;
        }
        const device_json: std.json.Parsed(std.json.Value) = try std.json.parseFromSlice(
            std.json.Value,
            state.allocator,
            devices_response.body.?,
            .{},
        );
        const devices = device_json.value.object.get("devices").?.array;
        if (devices.items.len == 0) {
            return error.NoDevices;
        }
        const device_id = devices.items[0].object.get("id").?.string;

        const queue_base_url = try std.fmt.allocPrint(
            state.allocator,
            "https://api.spotify.com/v1/me/player/queue?device_id={s}&",
            .{device_id},
        );
        const auth_header = try std.fmt.allocPrint(
            state.allocator,
            "Bearer {s}",
            .{state.token},
        );
        var headers = [_]std.http.Header{
            .{ .name = "Authorization", .value = auth_header },
            .{ .name = "Content-Type", .value = "application/x-www-form-urlencoded" },
        };
        var allowed_statuses = [_]u16{ 200, 204 };

        var queue_progress: QueueProgress = .{
            .current = 0,
            .total = state.uris.len,
        };
        const msg = try std.json.Stringify.valueAlloc(state.allocator, queue_progress, .{});
        const formatted_msg = try std.fmt.allocPrint(state.allocator, "data: {s}\n\n", .{msg});
        try writer.write(formatted_msg);

        const result = try state.allocator.create(multitool.Response);
        for (state.uris) |uri| {
            const queue_url = try std.fmt.allocPrint(state.allocator, "{s}uri={s}", .{ queue_base_url, uri });
            const queue_args = multitool.RequestArgs{
                .url = queue_url,
                .method = .POST,
                .headers = headers[0..],
                .body = null,
                .allowed_statuses = allowed_statuses[0..],
            };
            multitool.makeRequest(state.allocator, queue_args, result) catch |err| {
                switch (err) {
                    error.InvalidStatusCode => {
                        zlog.err("Failed to queue track {s}: Invalid status code received - {d}", .{ uri, result.status_code });
                        if (result.body) |body| {
                            zlog.err("Response body: {s}", .{body});
                        }
                        return err;
                    },
                    else => {
                        zlog.err("Failed to queue track {s}: {s}", .{ uri, @errorName(err) });
                        return err;
                    },
                }
            };
            queue_progress.current += 1;
            const updated_msg = try std.json.Stringify.valueAlloc(state.allocator, queue_progress, .{});
            const formatted_updated_msg = try std.fmt.allocPrint(state.allocator, "data: {s}\n\n", .{updated_msg});
            try writer.write(formatted_updated_msg);
        }
    }
};

fn playlistStream(_: *tanuki.Request, res: *tanuki.Response) anyerror!void {
    try res.streamResponse(State{}, State.handle);
}

pub fn queuePlaylist(app: *Server, req: *tanuki.Request, res: *tanuki.Response) anyerror!void {
    if (try isAuth(app, req, res) == false) {
        try res.write(.unauthorized, "{\"error\": \"No token found\"}");
        return;
    }
    const token = utils.getToken(req, res);
    if (token == null) {
        return error.NoToken;
    }

    const playlist_id = req.params.?.get("id");
    if (playlist_id == null) {
        return error.ParamsMissing;
    }

    const url = try std.fmt.allocPrint(
        res.arena,
        "https://api.spotify.com/v1/playlists/{s}",
        .{playlist_id.?},
    );

    const tracks_result = try utils.spotifyRequest(res.arena, url, req, res);
    const parsed: std.json.Parsed(std.json.Value) = try std.json.parseFromSlice(std.json.Value, res.arena, tracks_result, .{});
    const tracks = parsed.value.object.get("tracks").?.object.get("items").?.array;

    var rand = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    var rng = rand.random();

    for (0..tracks.items.len) |i| {
        const j = rng.intRangeLessThan(usize, i, tracks.items.len);
        const temp = tracks.items[i];
        tracks.items[i] = tracks.items[j];
        tracks.items[j] = temp;
    }

    var uris = std.ArrayList([]const u8).empty;
    for (tracks.items) |track| {
        const uri = track.object.get("track").?.object.get("uri").?.string;
        try uris.append(res.arena, try res.arena.dupe(u8, uri));
    }

    try res.streamResponse(State{
        .uris = try uris.toOwnedSlice(res.arena),
        .allocator = res.arena,
        .token = token.?,
    }, State.handle);
}

fn logout_helper(res: *tanuki.Response) !void {
    try res.setCookie(.{
        .name = "AccessToken",
        .value = "",
        .expires_at = "Thu, 01 Jan 1970 00:00:00 GMT",
        .path = "/",
    });
    try res.setCookie(.{
        .name = "RefreshToken",
        .value = "",
        .expires_at = "Thu, 01 Jan 1970 00:00:00 GMT",
        .path = "/",
    });

    try res.headers.append(res.arena, .{ .name = "Location", .value = "/" });
    try res.write(.see_other, "");
}

pub fn logout(_: *Server, _: *tanuki.Request, res: *tanuki.Response) anyerror!void {
    try logout_helper(res);
}
