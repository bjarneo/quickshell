# gamehud

A small cockpit panel in the top-right corner. Stays hidden until a game-class window is focused, then fades in with CPU, RAM, and (Nvidia) GPU readouts. Click-through, so the running game keeps mouse and keyboard.

The trigger is Hyprland's event socket (`.socket2.sock`). Every `activewindow` event is matched against a regex list; first hit flips the HUD on.

## Run

```sh
qs -n -d -c gamehud
```

Bind a manual toggle in Hyprland:

```
bind = SUPER SHIFT, G, exec, qs -c gamehud ipc call hud toggle
```

## Customize the trigger list

Drop a `games.json` next to the example file:

```sh
cp ~/.config/quickshell/gamehud/games.example.json ~/.config/quickshell/gamehud/games.json
$EDITOR ~/.config/quickshell/gamehud/games.json
qs -c gamehud ipc call hud reloadConfig
```

Each entry is a JavaScript regex tested against the focused window's `class`. Find the class with `hyprctl activewindow` while the game is focused. Anchor with `^...$` for an exact match, drop the anchors for a substring match. `\\.exe$` (with the doubled backslash) catches anything Wine launches.

## IPC

```
qs -c gamehud ipc call hud show          # force visible
qs -c gamehud ipc call hud hide          # force hidden
qs -c gamehud ipc call hud toggle        # flip forceShow
qs -c gamehud ipc call hud peek          # show for 4s then hide
qs -c gamehud ipc call hud reloadConfig  # re-read games.json
```

## Metrics

| Metric | Source |
| --- | --- |
| CPU% | `/proc/stat` delta, 1s cadence |
| RAM% / MEM | `/proc/meminfo` |
| GPU / TMP / PWR | `nvidia-smi --query-gpu=...`, 2s cadence |

If `nvidia-smi` is missing, the GPU column dims to `--`. AMD is not wired in yet (parsing `sensors` per card is fiddly); patches welcome.

## Why click-through

Wayland surfaces accept input across their whole bounds by default. The HUD uses `mask: Region {}` to declare an empty input region: pixels render, clicks fall through to whatever is underneath. This is the same trick `clipboard-ripple` uses.

## Theming

Reads `~/.config/omarchy/current/theme/colors.toml` for `background`, `foreground`, `accent`, `color1`, `color8`. Re-themes live on `omarchy theme set`. Per repo style: monospace only, no serif in instrument-panel widgets.
