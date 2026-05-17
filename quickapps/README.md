# quickapps

A radial quick-app launcher for [omarchy](https://omarchy.org). Eight to ten apps arranged around a single faint indigo ring, kanji counter in the top-right, serif typography. Colours follow the live omarchy palette, so it restyles itself whenever you run `omarchy theme set <name>`.

## Quick start

```sh
# One-shot launch from a Hyprland keybind (bindings.lua):
hl.bind("SUPER + A", hl.dsp.exec_cmd("qs -n -c quickapps"), { description = "Quick apps" })

# Or run it directly.
qs -n -c quickapps
```

The overlay grabs keyboard focus and exits on app launch or Esc. No daemon, no IPC, no tray icon. Reload Hyprland (`hyprctl reload`) after wiring the bind.

## Configuration

Edit `~/.config/omarchy-quickapps/apps.json` (create the dir if it doesn't exist). Falls back to `quickapps.example.json` shipped with this module.

```json
{
  "apps": [
    { "name": "TERMINAL", "icon": "ghostty",  "exec": "ghostty" },
    { "name": "BROWSER",  "icon": "chromium", "exec": "chromium" },
    { "name": "EDITOR",   "icon": "nvim",     "exec": "omarchy-launch-or-focus-tui nvim" }
  ]
}
```

| Field | Required | Notes |
| --- | --- | --- |
| `name` | yes | Rendered lowercase in the centre and beneath each disk. Keep it short, one or two words. |
| `icon` | no | Either an icon theme name (`firefox`, `chromium`, `obsidian`) or an absolute path. Resolved via `Quickshell.iconPath()`. Falls back to the first letter of `name` if missing or unresolved. |
| `exec` | yes | Run as `setsid -f sh -c "<exec>"`. Anything a shell would accept works (flags, pipes, `omarchy-launch-or-focus-tui ...`). |
| `comment` | no | Sub-label under the centred app name. Falls back to `exec` if unset. |

Eight to ten entries look best on the ring. Beyond ten the circle still works, but disks start crowding.

## Keys

| Key | Action |
| --- | --- |
| Left / Right / H / L / Up / Down / J / K | Rotate selection |
| Tab / Shift+Tab | Rotate selection |
| Scroll wheel | Rotate selection |
| 1 to 9 | Jump to and launch the nth app |
| Home / End | Jump to first / last |
| Enter / Space | Launch the selected app |
| Esc / Q | Dismiss |
| Click outside the ring | Dismiss |
| Click a disk | Select and launch |

## Theme reactivity

Reads `~/.config/omarchy/current/theme/colors.toml` and remaps the original Kanagawa Dragon roles:

| toml key | role |
| --- | --- |
| `background` | overlay base, focused-disk text fill |
| `foreground` | primary text, focused-disk colour |
| `color7` | reserved for bright secondary text |
| `color8` | muted text, idle index numerals, divider |
| `accent` | ring guide, idle disk border |
| `color1` | active position kanji, focus dot, enter hint |

`omarchy theme set <name>` rebuilds the theme dir atomically, which invalidates the inotify watch on `colors.toml`. A second `FileView` watches `~/.config/omarchy/current/theme.name` (rewritten in place, stable inode) as a swap beacon and force-reloads the palette. Same trick as the bar.

## Layout

- A single faint indigo ring at radius 230, no spokes, no gradient, no inner second ring.
- Disks 56px, idle fill is the background lightened by 15% so circles read on any palette.
- The selected disk inverts to the foreground colour and scales to 1.08; everything else is one of two muted states.
- The "静" (stillness) kanji washes the right half at 6% alpha. Removing it leaves the layout balanced but loses the seal of the original design.

## Files

```
quickapps/
  shell.qml                # entry point
  quickapps.example.json   # sample apps list (used when ~/.config/omarchy-quickapps/apps.json is missing)
  README.md
```
