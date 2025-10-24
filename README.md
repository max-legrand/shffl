# Shffl

Shffl is a web app for truly randomizing your playlist experience.

![shffl](/screenshots/shffl.png)

## How to Use
Under normal circumstances, I would host this app publicly for others to use. However, as of [Apr 15, 2025](https://developer.spotify.com/blog/2025-04-15-updating-the-criteria-for-web-api-extended-access),
Spotify no longer allows individual developers to apply for Web API Extended Access.
While I do host this app, Spotify imposes limits of up to 25 users per app and 5 new user signups per 24-hour period.
As such, the best way for you to use this app is to host it yourself.

## Setup
First, create a Spotify Developer account and register an app [here](https://developer.spotify.com/dashboard/applications).

Once your app is created, note your Client ID and Client Secret.

Next, build the app from source. It has two dependencies:
- [Zig](https://ziglang.org/download/) (v0.15.1 or higher)
- A JavaScript package manager ([pnpm](https://pnpm.io/installation), [Bun](https://bun.com/docs/installation), or npm). Many systems already have npm installed.
I recommend pnpm.

If you have Docker installed, you can build with the `./build.sh` script, which bundles the frontend and builds an x86_64 Linux binary. If you do not have Docker, follow the manual steps below.

```bash
# From the repo root
cd web
pnpm install
pnpm run build
cd ..
zig build --release=safe
```

Create a `.env` file in the project root with the following:
```.env
CLIENT_ID=<YOUR_CLIENT_ID>
CLIENT_SECRET=<YOUR_CLIENT_SECRET>
REDIRECT_URI=<YOUR_REDIRECT_URI>
```
If you are hosting the app locally, set `REDIRECT_URI` to `http://127.0.0.1:5882/callback`, and use this same value in your Spotify Developer app.
Note: If you are running with Docker, replace port `5882` with `5900`.

If you are hosting the app publicly, set `REDIRECT_URI` to `https://<YOUR_DOMAIN>/callback`, and use this value in your Spotify Developer app.

## Running

### With Docker
Run `docker compose up -d` and access the app at `http://localhost:5900`.

### Without Docker
Run `./zig-out/bin/shffl` and access the app at `http://localhost:5882`.

## Accessing the App on Other Devices
There are multiple ways to access the app from other devices. My preference is to self-host on a VPS (I like Hetzner + Coolify), though this incurs cost (and any additional costs for a custom domain).

Other options include:
- Using a service like Tailscale to create a VPN between your devices. This is my preferred approach when not hosting publicly.
- Using a tool like ngrok to create a tunnel to your local machine.

If you want to try the app before going through the effort of hosting, you can reach out [here](https://github.com/max-legrand/shffl/discussions/1)
