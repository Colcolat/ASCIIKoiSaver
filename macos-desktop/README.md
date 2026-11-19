# ASCII Koi Desktop — macOS Live Wallpaper & Useful Koi

A lightweight native macOS Menu Bar app (`ASCIIKoiDesktop.app`) that turns your desktop into the live ASCII Koi Pond behind your icons and widgets, with **smart 0% CPU auto-pause in fullscreen**, **reactive AI Agent Koi (Gemini & Claude)**, and a **Trash-Eater Koi**.

## Features

- **Desktop-Level Live Wallpaper**: Runs behind desktop icons, widgets, Dock, and windows (`CGWindowLevelForKey(.desktopWindow)`), never blocking clicks (`ignoresMouseEvents = true`).
- **Smart Fullscreen Auto-Pause**: Automatically detects fullscreen or maximized windows (and screen lock) and stops rendering completely (0% CPU) until the desktop is visible again.
- **Reactive AI Agent Koi (Gemini & Claude)**:
  - Automatically detects active Antigravity sessions, `claude`/`gemini` CLI processes, or custom hooks via `~/.ascii-koi/agents.json`.
  - **Gemini skin**: electric blue → violet → glowing cyan `*` sparkles.
  - **Claude skin**: warm terracotta, amber & pearly cream.
  - **Reactive states**: `thinking` (calm circling + bubbles), `editing` (fast agile swimming + ripple trail), `waiting` (surfaces with rhythmic ripples), `error` (alert flash), `done` (triumphant breach jump & exit), plus smaller companion subagent Koi.
- **Trash-Eater Koi (`~/.Trash`)**:
  - Curious visual visit when new files enter Trash (never auto-deletes).
  - Click **Feed Trash to Koi (`⌥⌘T`)** in the Menu Bar (with confirmation) to send the Trash-Eater Koi to your Dock's Trash corner, gobble ASCII crumbs, and empty the Trash.
- **Minimalist Mode**: Toggle between the full pond ecosystem and a clean Koi + Agents + Trash-only mode.

## Custom Agent Hook Format (`~/.ascii-koi/agents.json`)

```json
[
  { "id": "main", "model": "gemini", "state": "editing", "subagents": 2 },
  { "id": "helper", "model": "claude", "state": "thinking", "subagents": 0 }
]
```

Valid `state` values: `thinking`, `editing`, `waiting`, `done`, `error`.

## Build & Install

```bash
chmod +x macos-desktop/build_and_install_desktop.sh
./macos-desktop/build_and_install_desktop.sh
open ~/Applications/ASCIIKoiDesktop.app
```
