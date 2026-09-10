# Running skiff + outboard in an airgapped environment

skiff (the dashboard, this repo) and outboard (the queue engine,
[mddeff/outboard](https://github.com/mddeff/outboard)) are stdlib-only and were
already written defensively: almost every outbound network call is
feature-gated, best-effort, short-timeout, and fails silently rather than
blocking. This doc is the full "what to grab while you're online, how to get
it running once you're not" checklist. Tracked in
[skiff#9](https://github.com/mddeff/skiff/issues/9).

## Read this first: the one thing that isn't skiff's to fix

skiff and outboard never call an LLM directly. They shell out to whichever
coding-agent CLI you're driving — `claude`, `codex`, `gemini`, Antigravity —
and each of those needs its own path to a model endpoint. That's either
direct internet access, or an internal proxy/gateway one of them can be
pointed at (Claude Code supports `ANTHROPIC_BASE_URL`, and Bedrock/Vertex
variants; Codex and Gemini have their own equivalents — check each CLI's own
docs).

If the airgapped network has no route to a model provider at all, nothing
below matters: there's no LLM for the orchestrator to orchestrate. Settle
this first.

## What to copy while you still have internet

Pull all of this on a networked machine, then move it across whatever
transfer mechanism your airgap uses (USB, an internal mirror, scp to a
jump host — this doc doesn't prescribe that part).

**Required:**

- A full checkout (or release tarball) of `mddeff/skiff`, pinned to the
  commit/tag you want. `git clone https://github.com/mddeff/skiff` or
  download a tarball from the repo's "Code → Download ZIP" / Releases page.
- A full checkout (or release tarball) of `mddeff/outboard`, same idea.
- Python 3.9+ if the target box doesn't already have it — grab an offline
  installer or a copy of your distro's package for it.
- `git` — same, if not already present on the target box.

**Only if you plan to use the corresponding feature:**

- The coding-agent CLI(s) you intend to run (`claude`, `codex`, `gemini`,
  Antigravity) plus whatever *their* airgap/private-endpoint story requires —
  that's each tool's own installer and docs, out of scope here.
- The `gh` CLI binary, only if the airgapped network can reach an internal
  GitHub Enterprise Server. Without network access to *some* GitHub host,
  `gh`-backed features (issue-based bug reports, PR automation, WatchTower's
  GitHub-Issues queue backend) simply stay off — the dashboard already
  detects this (`gh_enabled = bool(which("gh"))`) and boots fine either way.

**Optional, cosmetic only — see "Self-hosting the two CDN assets" below if
you want these instead of the graceful fallback:**

- `mermaid.min.js` (currently loaded lazily from
  `https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js`, only when a
  transcript contains a mermaid code block).
- The three Google Fonts families the dashboard links to: Inter,
  JetBrains Mono, Space Grotesk (currently loaded from
  `fonts.googleapis.com` / `fonts.gstatic.com`).

Not vendoring either of these into the repo today — this section is the "how
to do it yourself later" reference, tracked as deferred work in skiff#9.

## Installing once you're inside the airgap

**Don't use `curl | bash`.** The one-line installer's whole point is fetching
the repo and phoning home for the initial clone — you've already brought the
repo with you, so skip it entirely.

### skiff

1. Place your pre-staged checkout at `~/.ccc/claude-command-center`
   (the default `CCC_INSTALL_DIR`), or anywhere and export
   `CCC_INSTALL_DIR=/your/path` before the next step.
2. `cd` into it and run `./run.sh` directly. This launches in the foreground
   and opens `http://localhost:8090` once the port answers — no network
   calls are made by this path.
3. If you ever do need to re-run `scripts/install.sh` against that same
   checkout (e.g. to pick up its service-install prompt), note that on the
   `airgap-support` branch its `git pull --ff-only` step no longer hard-fails
   the whole installer when there's no network — it warns and continues with
   the checkout as-is. (Unpatched `main` would abort under `set -euo
   pipefail` if that pull fails offline — another reason to prefer `./run.sh`
   directly until that lands.)

### outboard

skiff's launch flow (`scripts/install-watchtower.sh`) looks for WatchTower in
this order, and **only the last one touches the network**:

1. A dev checkout at `$WATCHTOWER_DIR`, `~/Apps/watchtower`, or
   `~/dev/watchtower` (any directory with a `pyproject.toml`). This tier is
   *never* auto-pulled by design — treat this as the airgap-friendly staging
   spot. Set `WATCHTOWER_DIR=/your/path` if you're not using one of the two
   default paths.
2. An existing CCC-managed clone at `~/.ccc/watchtower` (or
   `$WATCHTOWER_INSTALL_DIR`) — if present, it's reused; a background
   `git pull --ff-only` refresh is attempted but its failure is already
   silently ignored, so this is safe offline too.
3. `git clone` from `$WATCHTOWER_REPO_URL` (default
   `https://github.com/mddeff/outboard`) — network required, skipped
   entirely if tier 1 or 2 already resolved.
4. A tarball download, then PyPI (`watchtower-cli`) as a last resort — both
   network-required, both skipped if an earlier tier resolved.

So: pre-stage your outboard checkout at one of the tier-1 or tier-2 paths and
no network call happens for it at all.

## Config worth setting

| Env var | Purpose |
|---|---|
| `CCC_TELEMETRY_DISABLED=1` | Kills the anonymous telemetry pings outright (daily ping, boot beacon, click counter). They're already fire-and-forget with a short timeout and fail silently offline, but this avoids even attempting the connection. |
| `CCC_INSTALL_DIR` | Where skiff's checkout lives, if not the default `~/.ccc/claude-command-center`. |
| `CCC_REPO_URL` | Only consulted if `scripts/install.sh` actually needs to clone — irrelevant once you're pre-staging checkouts. |
| `WATCHTOWER_DIR` | Point at your pre-staged outboard dev checkout (tier 1 above). |
| `WATCHTOWER_INSTALL_DIR` / `WATCHTOWER_REPO_URL` | Same idea as the `CCC_*` pair, for outboard's own tiers 2/3. |

## What degrades offline (by design, not a bug)

These already fail gracefully with no code changes needed — listed here so
it's clear what "degrade" means for each:

- **Update check** (`api.github.com/repos/...`) — only runs when you hit the
  "check for updates" action; 5s timeout, fails silently.
- **Claude model catalog refresh** (`platform.claude.com`) — has no live
  caller path in `server.py` today; when it does run, it preserves the last
  cached catalog on any failure.
- **`gh`-backed features** — off entirely without a reachable `gh`; detected
  at boot, not a crash.
- **Google Fonts** — falls back to system fonts. Purely visual.
- **Mermaid diagrams** — falls back to showing the raw diagram source in a
  `<pre>` block instead of a rendered SVG. Already has this fallback built
  in (`static/app.js`, the `mermaid-source` element).

## Self-hosting the two CDN assets (optional, not done today)

Only worth doing if you want mermaid diagrams to actually render and/or want
zero external DNS lookups from the dashboard's HTML (rather than the silent
fallback above, which is otherwise harmless).

**Mermaid:**

1. On a networked machine: `curl -o mermaid.min.js https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js`
2. Copy it into `static/vendor/mermaid.min.js` (new directory) in your
   airgapped checkout.
3. Find where `static/app.js` lazy-loads the CDN URL (search for
   `cdn.jsdelivr.net` — it's the mermaid lazy-load promise near the
   `_mermaidLoadPromise` code) and point the `<script src>` it injects at
   `/static/vendor/mermaid.min.js` instead.

**Fonts:**

1. On a networked machine, use Google Fonts' "Download family" for Inter,
   JetBrains Mono, and Space Grotesk (or `google-webfonts-helper` to get
   pre-subset `woff2` files with matching `@font-face` CSS).
2. Copy the `woff2` files into `static/fonts/` (new directory).
3. In `static/index.html`, replace the three `<link>` tags (the two
   `preconnect`s and the `fonts.googleapis.com/css2?...` stylesheet, around
   line 35-37) with a local `<link rel="stylesheet" href="/static/fonts/fonts.css">`
   where `fonts.css` declares `@font-face` rules pointing at the local
   `woff2` files, using the same family names/weights the app already
   references (`Inter`, `JetBrains Mono`, `Space Grotesk`).

Both changes are self-contained and low-risk — they replace a URL, not any
application logic — but are left undone here per scope.

## Post-install sanity check

Once `./run.sh` is running and `http://localhost:8090` answers:

- `curl http://localhost:8090/api/version` → 200, confirms the server itself
  needs nothing external to boot.
- `curl http://localhost:8090/api/features` → confirms which optional
  features (morning view, `gh`-backed, etc.) are active given what's
  installed.
- Open the dashboard in a browser and confirm it loads — expect the page to
  render with system fonts instead of Inter/JetBrains Mono/Space Grotesk
  unless you did the font vendoring above; that's cosmetic only.
