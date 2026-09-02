# GitHub Notifier plugin for DankMaterialShell

Shows a compact badge in the DankBar with counts for open Pull Requests authored by you and Issues assigned to you, using the `gh` CLI. Includes a popup with a breakdown and quick links to GitHub filtered for the current user.

![Screenshot](./screenshot.png)

## Features

- Badge in the bar showing the total count (PRs + issues)
- Popup header card with your avatar, username, active item count and the time
  of the last refresh
- One card per category listing the actual pull requests and issues — title and
  `repo #number` — each opening in the browser on click
- Lists scroll, with their own scrollbar, past three items
- Manual refresh with a spinner that tracks the real `gh` calls, and a toast when
  it completes
- Optional filter by GitHub organization
- Configurable refresh interval, time format, and what to count (PRs/issues)

## Installation

```bash
mkdir -p ~/.config/DankMaterialShell/plugins/
git clone <this-repo-url> githubNotifier
```

Then enable the plugin via DMS Settings → Plugins and add the `githubNotifier` widget to your DankBar.

## Usage

1. Open DMS Settings (Super + ,)
2. Enable the `GitHub Notifier` plugin
3. Optionally set an `Organization` to filter results to a specific org
4. Configure `gh binary` if not simply `gh`
5. The widget will query `gh` periodically (configurable) and update counts

## Settings

- `Organization`: optional. Filters PRs and issues to the specified GitHub organization.
- `ghBinary`: binary name/path (default: `gh`).
- `refreshInterval`: seconds between automatic refreshes. Values below 15 are
  clamped to 15.
- `Show Pull Requests`: toggle to include/exclude open PRs authored by you.
- `Show Issues`: toggle to include/exclude open issues assigned to you.
- `Time Format`: how the last-updated time is rendered in the popup header —
  system default, 12-hour or 24-hour.

## Files

- `plugin.json` — plugin manifest
- `GitHubNotifierWidget.qml` — main widget and popup implementation
- `GitHubNotifierSettings.qml` — settings UI
- `README.md` — this file

## Permissions

This plugin requests:

- `process` — to run the `gh` CLI
- `settings_read` / `settings_write` — to read and persist plugin settings

## Requirements

- `gh` CLI installed, authenticated, and available in PATH or referenced via `ghBinary` setting.
- `Font Awesome` (e.g. Font Awesome 6 Brands) — required so the GitHub icon displays correctly.

## How it works

The plugin executes `gh` commands, in this order:

- Check the `gh` binary: `gh --version`
- Check authentication: `gh auth status`
- Fetch your profile once, for the popup header:
  `gh api user --jq '{html_url,avatar_url,login}'`
- Pull requests: `gh search prs archived:false --author=@me --state=open [--owner=<org>] --json number,title,url,repository --limit 25`
- Issues: `gh search issues archived:false --assignee=@me --state=open [--owner=<org>] --json number,title,url,repository --limit 25`

Archived repositories are excluded, and each list is capped at 25 items. The
widget parses the JSON as an array, or as an object with an `items` array.

Refreshes are serialised: while one is in flight another is queued rather than
run in parallel, and a watchdog clears the in-flight state if a command never
returns.

## Troubleshooting

- If counts are zero but the CLI shows results, check `ghBinary` setting and ensure `gh` works in a terminal: `gh search prs --author=@me --state=open --json number`
- If `gh` is not authenticated, run: `gh auth login`

## Contributors

- [Lucas Mariani](https://github.com/psyreactor) — author
- [rochacbruno](https://github.com/rochacbruno) — exclude archived repositories ([#5](https://github.com/psyreactor/dms-githubNotifier/pull/5))
- [Thomas-Philippot](https://github.com/Thomas-Philippot) — header with user info and SVG icon ([#2](https://github.com/psyreactor/dms-githubNotifier/pull/2))
- [bernardopg](https://github.com/bernardopg) — serialize refreshes and DMS 1.5 color fix ([#6](https://github.com/psyreactor/dms-githubNotifier/pull/6))
- [martian0x80](https://github.com/martian0x80) — fix broken vertical bar pill ([#9](https://github.com/psyreactor/dms-githubNotifier/pull/9))
- [rdannenbring](https://github.com/rdannenbring) — fix widget hanging on "Checking..." in multi-bar setups ([#11](https://github.com/psyreactor/dms-githubNotifier/pull/11))
- [JDKamalakar](https://github.com/JDKamalakar) — UI rework to match the official Phone Connect plugin: scrollable lists, header card, configurable time format ([#13](https://github.com/psyreactor/dms-githubNotifier/pull/13))
