# dev.notch

A fork of [Boring Notch](https://github.com/TheBoredTeam/boring.notch) that turns the MacBook notch into a status strip for working with coding agents. You can see at a glance whether Claude Code or Codex is working, done, or waiting on you. It also shows when your traffic is going through a VPN, and it has a one-click replacement for `caffeinate -d`.

Everything Boring Notch already does still works: the music live activity and visualizer, calendar, the file shelf with AirDrop, system HUD replacement and the webcam mirror. This README covers what the fork adds and how to build it. For the rest, see the [upstream README](https://github.com/TheBoredTeam/boring.notch#readme).

## What the fork adds

### Coding agent status (Claude Code and Codex)

- **A dot on the closed notch** (right edge) shows the state of the most urgent session:
  - **blue**: working
  - **orange, pulsing**: blocked, waiting for your approval or input
  - **green**: finished its turn
- **A heads-up when an agent gets blocked.** The closed notch briefly shows the project name and the agent's message, such as "needs approval". Click it to jump to the window the agent is running in.
- **An agent panel in the open notch** lists every live session with its project, state and last message. Click a row to focus that session's window.
- **Window focus** works with VS Code, Cursor, iTerm2, Terminal, Ghostty, WezTerm and Alacritty. With Accessibility permission the exact window is raised. Without it, the app is only brought to the front.
- **Only real waits count as blocked**: permission prompts, idle prompts and input requests. Informational notifications don't count. A session goes back to "working" as soon as you approve a tool or reply.
- **Silent sessions are dropped** after 30 minutes. You can change this in settings.

### VPN dot

A blue dot on the left edge of the closed notch means your default route goes through a tunnel interface (`utun`, `ipsec`, `ppp`, `tun`, `tap`). It reads the route the system actually uses, not just whether a tunnel interface exists, so the dot means "my traffic is tunnelled right now". It listens for network change events instead of polling.

- **Ignore list.** iCloud Private Relay and an idle Tailscale daemon also create `utun` devices. Settings shows the current primary interface, so you can add that exact name to the ignore list.
- **Optional egress IP lookup.** This is off by default because it sends a request to a third party (`api.ipify.org`) on every network change.

### Keep display awake

The in-app equivalent of `caffeinate -d`. While it's on, the display won't dim or sleep, and so neither does the Mac.

- **Ways to toggle it:** the moon button in the open notch header, **Keep Display Awake** in the menu bar menu, or Settings → Dev Status.
- **A glowing full moon** sits on the left of the closed notch while it's on.
- **It holds a power assertion directly instead of spawning `caffeinate`.** macOS releases it automatically if the app quits or crashes, so nothing is left keeping your screen on. You can see it with `pmset -g assertions`, listed as "Keep Display Awake".
- **The choice is remembered** across app restarts.

### Smaller changes

- **Choose the middle panel of the open notch:** none, calendar, or agent sessions.
- **Shelf:** <kbd>⌘</kbd><kbd>⌫</kbd> removes the selected items, and clicking an item no longer clears the selection.
- **A Dev Status settings pane** brings all of the above together.

## Building and installing

There are no prebuilt releases of this fork. You build it from source.

**Requirements:** Xcode 26 or later on macOS 15.6 or later to build. The app itself runs on macOS 14 Sonoma or later.

```bash
git clone https://github.com/schlmpcs/dev.notch.git
cd dev.notch
./Scripts/install.sh
```

`install.sh` does the following:

1. Builds the Release configuration.
2. Stops the running copy.
3. Moves the previous `/Applications/boringNotch.app` to a temporary backup folder and prints its path.
4. Installs the new build and launches it.

Run it again whenever you pull changes.

> [!NOTE]
> Run the copy in `/Applications`, not the build Xcode launches with <kbd>⌘</kbd><kbd>R</kbd>. If both run at once you get two notches drawing over each other.

The fork keeps upstream's bundle identifier, so it replaces an existing Boring Notch install and picks up its settings.

### Optional: reinstall on every push

To rebuild and reinstall automatically each time you push, add a `pre-push` hook. It runs in the background, so the push doesn't wait, and it shows a notification if the build fails:

```bash
cat > .git/hooks/pre-push <<'EOF'
#!/bin/sh
LOG=/tmp/boringnotch-install.log
{
  ./Scripts/install.sh > "$LOG" 2>&1 ||
    osascript -e "display notification \"Build failed. tail $LOG\" with title \"boringNotch\""
} </dev/null >/dev/null 2>&1 &
exit 0
EOF
chmod +x .git/hooks/pre-push
```

## Setting up agent status

The agents report their state through a small hook script that the app writes into its own container. You do this setup once.

1. Open **Settings → Dev Status → Hook setup**.
2. Click **Copy Claude hook config** and merge it into the `hooks` section of `~/.claude/settings.json`. For Codex, click **Copy Codex hook config** and merge it into `~/.codex/hooks.json`.
3. Click **Copy de-quarantine command** and run it once in Terminal. macOS won't run a file that a sandboxed app wrote until it's been de-quarantined. Run it again only if an app update changes the script.
4. Restart your agent sessions. Codex asks you to trust the hook the first time it runs.
5. For exact window focus, grant boringNotch **Accessibility** permission in System Settings → Privacy & Security. Boring Notch already asks for this for HUD replacement.

### How it works

Each hook call writes one event file into a queue folder inside the app's sandbox container:

- **Line 1** is a header with the agent, the terminal and the tty.
- **The rest** is the agent's JSON payload, passed through unchanged.

The app watches that folder, reads each file into memory and deletes it, so nothing piles up on disk. The script needs nothing beyond `/bin/sh`: no `jq`, no Python, no network.

## Development

`Scripts/selfcheck.sh` compiles the dependency-free logic on its own and checks it in a few seconds, with no Xcode build:

- VPN interface classification
- Hook payload parsing for Claude and Codex
- The session reducers
- The generated hook configs

```bash
./Scripts/selfcheck.sh
```

The fork's code lives in `boringNotch/devstatus/`.

## Credits

dev.notch is built on [Boring Notch](https://github.com/TheBoredTeam/boring.notch) by TheBoredTeam and its contributors. All the core notch work is theirs. If you want the original app, prebuilt releases, or a place to contribute to the main project, go there. Boring Notch in turn credits [MediaRemoteAdapter](https://github.com/ungive/mediaremote-adapter) and [NotchDrop](https://github.com/Lakr233/NotchDrop). See [THIRD_PARTY_LICENSES](./THIRD_PARTY_LICENSES) for the full list.

## License

GPL-3.0, the same as upstream. See [LICENSE](LICENSE).
