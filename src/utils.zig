const std = @import("std");
const multitool = @import("multitool");
const tanuki = @import("tanuki");
const server = @import("server.zig");
const Server = server.Server;
const zlog = @import("zlog");

pub fn extractTokenFromCookie(headers: *const std.ArrayList(std.http.Header), token_name: []const u8) ?[]const u8 {
    for (headers.items) |header| {
        if (std.mem.eql(u8, header.name, "Cookie") or std.mem.eql(u8, header.name, "Set-Cookie")) {
            const cookie = header.value;
            var cookie_idx: usize = 0;

            while (cookie_idx < cookie.len) {
                if (std.mem.startsWith(u8, cookie[cookie_idx..], token_name)) {
                    const eq_idx = cookie_idx + token_name.len;
                    if (eq_idx < cookie.len and cookie[eq_idx] == '=') {
                        const start = eq_idx + 1;
                        const end = std.mem.indexOf(u8, cookie[start..], ";") orelse cookie.len - start;
                        return cookie[start .. start + end];
                    }
                }

                if (std.mem.indexOf(u8, cookie[cookie_idx..], ";")) |semi_idx| {
                    cookie_idx += semi_idx + 2;
                } else {
                    break;
                }
            }
        }
    }
    return null;
}

pub fn getToken(req: *tanuki.Request, res: *tanuki.Response) ?[]const u8 {
    const res_token = extractTokenFromCookie(&res.headers, "AccessToken");
    if (res_token) |token| {
        return token;
    }
    const req_token = extractTokenFromCookie(&req.headers, "AccessToken");
    return req_token;
}

const TokenResult = struct {
    access_token: []const u8,
};

pub fn refreshAccessToken(arena: std.mem.Allocator, refresh_token: []const u8, app: *Server) anyerror![]const u8 {
    const request_body = try std.fmt.allocPrint(
        arena,
        "grant_type=refresh_token&refresh_token={s}&client_id={s}&client_secret={s}",
        .{
            refresh_token,
            app.cfg.client_id,
            app.cfg.client_secret,
        },
    );

    const request_args = multitool.RequestArgs{
        .url = "https://accounts.spotify.com/api/token",
        .method = .POST,
        .headers = &[_]std.http.Header{
            .{ .name = "Content-Type", .value = "application/x-www-form-urlencoded" },
        },
        .body = request_body,
    };
    const result = try arena.create(multitool.Response);
    defer arena.destroy(result);

    try multitool.makeRequest(arena, request_args, result);
    const result_trimmed = std.mem.trim(u8, result.body.?, " \t\n\r");

    const result_json: TokenResult = std.json.parseFromSliceLeaky(TokenResult, arena, result_trimmed, .{
        .ignore_unknown_fields = true,
    }) catch |err| {
        zlog.err("Failed to parse token response: {}", .{err});
        return err;
    };
    const token = result_json.access_token;
    return token;
}

pub fn spotifyRequest(arena: std.mem.Allocator, url: []const u8, req: *tanuki.Request, res: *tanuki.Response) anyerror![]const u8 {
    const current_token = getToken(req, res);

    if (current_token == null) {
        return error.NoToken;
    }

    const auth_header = try std.fmt.allocPrint(arena, "Bearer {s}", .{current_token.?});
    var headers = [_]std.http.Header{
        .{ .name = "Authorization", .value = auth_header },
        .{ .name = "Accept-Encoding", .value = "identity" },
    };

    const request_args = multitool.RequestArgs{
        .url = url,
        .method = .GET,
        .headers = headers[0..],
        .body = null,
    };

    const result = try arena.create(multitool.Response);
    defer arena.destroy(result);
    try multitool.makeRequest(arena, request_args, result);
    if (result.status_code == 401) {
        return error.Unauthorized;
    }
    return result.body.?;
}
