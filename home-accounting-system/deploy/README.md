# Deploying Cromberg

Vendored copy of [z17/home-accounting-system](https://github.com/z17/home-accounting-system)
(GPL, see `../LICENSE`) at upstream commit `7c02aae`, plus the deploy helpers in
this folder. Nothing in `../app` or `../server` has been modified.

## What this project actually is

It is two separate programs, and only one of them belongs on a server:

| Part | What it is | Runs on a server? |
| --- | --- | --- |
| `../app` | Electron desktop app (React UI + NeDB file database) | **No** |
| `../server` | PHP 8 + MySQL web service | **Yes** |

The desktop app is the product. Its React UI talks to the Electron main process
over IPC (`ipcRenderer` in nearly every component), and the data lives in a
local NeDB file under the OS user-data directory. There is no HTTP server in it
and no multi-user story — you cannot host it and point a browser at it.

`server/` is the small companion service the desktop app calls out to: monthly
email reminders, currency rates, a version check, and a stats page. That is the
piece you deploy.

## Server component

### Requirements

- PHP 8 with `pdo_mysql` (verified on 8.4)
- MySQL or MariaDB (verified on MariaDB 10.11)
- Apache with `mod_rewrite` — `server/www/.htaccess` rewrites all non-file
  requests to `index.php`, and `index.php` dispatches on `$_SERVER['REDIRECT_URL']`,
  which mod_rewrite sets. On nginx you must set that variable yourself, e.g.
  `fastcgi_param REDIRECT_URL $uri;` with a `try_files ... /index.php` fallback.

### Setup

```sh
DB_PASSWORD='<pick one>' DOMAIN='cromberg.example.com' ./deploy/setup-server.sh
```

This creates the database and user, applies every migration in `server/db` in
order, and writes `server/www/Cromberg/Config.php` from the example. The
migrations are date-prefixed and **must** run in sequence — the first file
creates only `emails` and `reminders`; `log`, `currency_rate`, `lang`, and the
timestamp columns arrive in the four later files. Applying only the first one
leaves the service throwing `Base table or view not found` on `/version`.

Then, by hand:

- Set `$exchangerate_key` in `Config.php` (an api.exchangerate.host key) or the
  currency endpoints return empty results.
- Point a vhost's document root at `server/www`, with `AllowOverride` set so the
  shipped `.htaccess` is honoured.
- Install the cron entries from `server/crontab/config.md`, substituting your own
  domain and the notify key printed by the setup script.

### Routes

`/`, `/email`, `/notify`, `/send-notify`, `/unsubscribe`, `/version`, `/stats`,
`/get_currencies`, `/update_today_currency`, `/update_old_currency`.

`/notify` is guarded by `$notify_key` and is a no-op except on the last day of
the month (`date('t') !== date('d')`), so an empty `reminders` table on any other
day is correct behaviour, not a failure.

### Local check without Apache

`deploy/router-dev.php` emulates the `.htaccess` rewrite for PHP's built-in
server, which is otherwise unusable here — without it every request falls
through to the landing page.

```sh
php -S 127.0.0.1:8080 -t server/www deploy/router-dev.php
```

Dev only. Do not serve production traffic from it.

### Note on the landing page

`server/www/resources/template/page-template.html` embeds the upstream author's
Yandex.Metrika analytics tag (counter `46850502`). If you host this yourself,
every visitor to your landing page is reported to that third-party account.
Remove the tag or replace the counter id before going live.

## Desktop app

```sh
cd app
npm install
cp db/database-dev-example database-dev   # sample data, dev only
npm run dev                               # or: npm start
```

`npm run dev` opens the app against `database-dev` with devtools; `npm start`
uses the real database under the OS user-data directory. Build installers with
`npm run react-build && npm run dist`.

The UI loads Google Charts from `www.gstatic.com` at runtime and the app queries
the upstream service for currency rates and version, so on a network that blocks
either, charts sit at "Loading Chart" and the console shows TLS/403 errors. The
rest of the UI — tables, totals, best/worst month — is computed locally and works
offline.

To run it headlessly (CI, or a box with no display):

```sh
Xvfb :99 -screen 0 1280x800x24 &
DISPLAY=:99 ./node_modules/electron/dist/electron . --dev --no-sandbox --disable-gpu
```

`--no-sandbox` is only needed when running as root.
