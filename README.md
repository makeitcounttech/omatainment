# OmaTainment

Music, YouTube video and Remux library controls in the Omarchy bar, with queue, pop-out playback and optional phone handoff. The public display name is OmaTainment; the repository name is omatainment and the plugin ID remains empire.omatainment. Maintained by makeitcount.tech.

## Requirements

Source baseline: Omarchy 4.0.4-1, Quickshell/QtQuick/QtMultimedia and shell Commons/Ui modules; Python 3; Bash; mpv; yt-dlp; ffmpeg; PipeWire tools (`pw-cat`) and optional NumPy for visualization. Remux, Docker-based local startup, KDE Connect and Moonfin/NewPipe phone integrations are optional and separately configured; no service, library, credential or phone is supplied.

## First run

Enable the widget in a fresh test account and configure your own media sources. Remux reads `~/.config/omatainment/remux.json` with `url`, `token` and `userId`; keep that file private and outside this checkout. A generic URL is `https://media.example.com`. Remote handoff requires an explicit `OMATAINMENT_REMOTE_SSH` value (for example `alice@example.com`) and `OMATAINMENT_REMOTE_REMUX` for the remote loopback URL. It refuses before reading credentials when the destination is unset or invalid. Destinations must be plain host/SSH aliases, optionally prefixed with a username; options, whitespace and shell syntax are rejected. The remote URL must use HTTP(S) and loopback (`localhost`, `127.0.0.1` or `[::1]`), with an optional valid port and simple path; userinfo, queries, fragments and shell punctuation are rejected. SSH options are terminated before the destination and every remote command argument is shell-quoted. Remote handoff assumes matching item/server identities. Only configure a trusted destination.

## Limitations

No media, audio, GUI, phone, network or install smoke test was performed. Third-party availability, content licensing and codec support are external dependencies. Only play content you have rights to access. The old remote-host-specific environment names are replaced by the generic REMOTE names above. Upstream marketing performance claims and marketplace badges are not verified and are omitted here.

## Credits and license

Fork of MaenExists/omaopus (https://github.com/MaenExists/omaopus), MIT. Original Copyright (c) 2026 MaenExists and the complete MIT notice remain in LICENSE. Manifest upstream links identify provenance, not the destination of this unpublished fork.

## Install

This is a local release-preparation tree, not a published repository. Publication requires separate approval. Do not install over an existing plugin without backing it up and reviewing conflicts.

For a fresh test account with no existing plugin, copy this repository's runtime files (excluding `.git`, `.github`, `scripts`, and `tests`) into `~/.config/omarchy/plugins/empire.omatainment/`, retaining the root `manifest.json` and its relative entry-point layout. Use the Omarchy plugin settings to enable it. No install, enable, or desktop restart has been exercised for this release preparation.

## Uninstall

Disable the plugin in Omarchy first, then remove only its own plugin directory. Back up any settings you want to keep; removing the plugin does not necessarily remove user state or external services. Do not stop a routing service with active capture.

## Development checks

Install Python 3.13, Node.js, ruff 0.17.2, shellcheck-py 0.11.0.1 and gitleaks 8.30.1. Run `bash scripts/privacy-scan.sh`, `python -B scripts/lint.py`, and `gitleaks dir . --redact`. After committing, run `bash scripts/privacy-scan.sh --commit HEAD` and `gitleaks git . --redact --log-opts=--all`. CI repeats these checks. QML lint runs when qmllint and its Qt/Quickshell imports are available; otherwise its absence is explicitly reported, not counted as a pass.

The privacy policy scans file names and contents, including untracked files, and can read committed blobs independently of the working tree. It rejects internal domains, shared-address-space IPs (no exceptions currently), personal home/work paths, agent identities, host roles, and unapproved emails. Omarchy as a platform/product/API name is allowed; Omarchy used as an SSH/HTTP host is not. The exact email allowlist is `alice@example.com` (documentation), `noreply@paperclip.ing` (commit attribution), and `hello@makeitcount.tech` (approved public author/committer identity only, not an email support channel). Examples use `example.com`, `192.0.2.10` or `198.51.100.11`; never real credentials.
