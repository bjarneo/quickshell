# quickshell

Personal [Quickshell](https://quickshell.outfoxxed.me) configs built for [omarchy](https://omarchy.org). They read the live omarchy palette at `~/.config/omarchy/current/theme/colors.toml`, so the bar and overlay restyle themselves whenever you run `omarchy theme set <name>`.

| Module | What it does |
| --- | --- |
| [`navbar/`](./navbar) | Minimal top bar. Kanagawa Dragon layout, kanji workspace markers, omarchy-theme-aware colors. Click-through popups for calendar, screenshots, display (warmth/brightness/gamma), and weather (wttr.in, manual location override). |
| [`omni-menu/`](./omni-menu) | Command palette. Fuses installed apps with the omarchy-menu (Style, Setup, Install, Remove, Update, System, Toggle, Trigger, Capture, Share, Learn) in one searchable list. Metadata-driven synonyms ("wallpaper" finds Background, "reboot" finds Restart). Theme-tinted app icons. Toggle via `qs ipc`. |
| [`song-drop/`](./song-drop) | MPRIS notifier. Drops a liquid blob from the bar on track change, morphs into a song-title pill, holds, then retreats. |
| [`song-slide/`](./song-slide) | MPRIS notifier, snappier sibling of song-drop. Slides a sharp-cornered card in from the right with title, artist, an accent stripe, and a flush bottom-edge progress bar. Cross-fades content on rapid track changes instead of restarting the slide. |
| [`theme-wash/`](./theme-wash) | Theme-swap flourish. On `omarchy theme set <name>`, washes the new accent across the bar from an alternating corner like ink spilling in water, with the old accent pulsing out from the centre and the new theme's name popping briefly mid-wash. |
| [`music-wallpaper/`](./music-wallpaper) | Music-reactive wallpaper. Reads `cliamp visstream` NDJSON, paints a soft radial pulse with mids halo, bass-transient ripples, and a low-opacity EQ across the bottom. Tints to the omarchy accent. |
| [`clipboard-ripple/`](./clipboard-ripple) | Clipboard tactile feedback. `wl-paste --watch` blooms a soft accent-tinted halo outward from the cursor while a brighter inner core pulses twice. Click-through overlay. |
| [`battery-drip/`](./battery-drip) | Rare, high-information battery feedback. Crossings of 20% / 10% drip a teardrop down the right edge of the bar; transition to Full (or plug-in already near full) fills a battery outline with a rising sinusoidal wave. Click-through overlay. |
| [`quickapps/`](./quickapps) | Radial quick-app launcher. Eight to ten favourite apps arranged around a single faint indigo ring with kanji counter and serif typography. Reads `~/.config/omarchy-quickapps/apps.json`; bind to a Hyprland key for a Spotlight-style launch. |

Each module is a self-contained Quickshell config rooted at `shell.qml`.

## Quick start

```sh
git clone https://github.com/bjarneo/quickshell ~/.config/quickshell

# disable omarchy's waybar (one-shot toggle, also bound to SUPER+SHIFT+SPACE)
omarchy toggle waybar

# launch the bar
qs -n -d -c navbar

# launch the omni-menu command palette daemon
qs -n -d -c omni-menu
# then toggle it from a Hyprland keybind, e.g.:
#   bind = SUPER, SPACE, exec, qs -c omni-menu ipc call palette toggle

# launch the song-drop overlay
qs -n -d -c song-drop

# launch the song-slide overlay (snappier sibling, anchored right)
qs -n -d -c song-slide

# launch the theme-wash flourish
qs -n -d -c theme-wash

# launch the music-reactive wallpaper (requires cliamp)
qs -n -d -c music-wallpaper

# launch the clipboard ripple
qs -n -d -c clipboard-ripple

# launch the battery drip / fill overlay
qs -n -d -c battery-drip

# launch the quickapps radial launcher (bind to a key, no daemon needed)
qs -n -c quickapps
```

`-c <name>` resolves to `~/.config/quickshell/<name>/shell.qml`. `-d` daemonizes, `-n` makes it idempotent.

For per-module setup (autostart hooks, theme reactivity details, customization knobs, troubleshooting), see [`navbar/README.md`](./navbar/README.md).

## Requirements

- quickshell
- hyprland
- omarchy (for the live theme palette and the `omarchy toggle waybar` flow)

navbar also wants `pamixer`, `bluetoothctl`, and `nmcli` for telemetry tiles, plus `brightnessctl` and `hyprsunset` for the display popup and `jq` + `curl` for the weather popup. song-drop only needs an MPRIS-capable player (mpv, spotify, etc.). music-wallpaper needs [`cliamp`](https://github.com/bjarneo/cliamp) on `PATH` for its `visstream` NDJSON feed. clipboard-ripple needs `wl-clipboard` (for `wl-paste`) and `python3` for the cursor/monitor query.

## License

MIT.
