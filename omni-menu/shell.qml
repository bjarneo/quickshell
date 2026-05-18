import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// Omni-menu. A single command palette that fuses installed apps (.desktop
// scan) with every action exposed by `omarchy-menu` — Style, Setup, Install,
// Remove, Update, System, Toggle, Trigger, Capture, Share, Learn. Search
// indexes title, category, and a curated synonym list per entry, so a query
// like "wallpaper" lands on Background, "dark mode" lands on Theme, "reboot"
// lands on Restart, etc.
//
// Visual language follows navbar/shell.qml: Kanagawa Dragon typography on
// the omarchy live palette (~/.config/omarchy/current/theme/colors.toml),
// mono caps with letter-spacing for headings, a centred card with a
// scale-from-centre reveal, Esc/Q to dismiss.
//
// Toggle from a Hyprland keybind:
//   bind = SUPER, SPACE, exec, qs ipc call palette toggle
ShellRoot {
    id: root

    // ---------- Theme paths (shared with navbar) ----------
    readonly property string colorsPath: Quickshell.env("HOME") + "/.config/omarchy/current/theme/colors.toml"
    readonly property string themeNamePath: Quickshell.env("HOME") + "/.config/omarchy/current/theme.name"

    // Scoring weights and result cap. omarchy-menu has ~125 entries plus the
    // 12 nav rows plus ~80-200 .desktop apps, so the cap lets a quick
    // page-down still reach near-matches without overdrawing.
    readonly property int scPrefix: 100
    readonly property int scTitle:  60
    readonly property int scKw:     20
    readonly property int scCat:    10
    readonly property int maxResults: 250

    // Palette defaults are Kanagawa Dragon; FileView below overwrites them
    // from the live omarchy palette on load and on every theme swap.
    property color paper:   "#181616"
    property color ink:     "#c5c9c5"
    property color inkDeep: "#c8c093"
    property color sumi:    "#a6a69c"
    property color indigo:  "#658594"
    property color seal:    "#c4746e"

    readonly property color bg:    Qt.rgba(paper.r, paper.g, paper.b, 0.96)
    readonly property color fg:    ink
    readonly property color muted: sumi
    readonly property color sep:   Qt.rgba(ink.r, ink.g, ink.b, 0.18)
    readonly property color rowHi: Qt.rgba(ink.r, ink.g, ink.b, 0.06)
    readonly property color rowSel: Qt.rgba(seal.r, seal.g, seal.b, 0.18)

    readonly property string mono:  "JetBrainsMono Nerd Font"
    readonly property string serif: "serif"

    // ---------- Visibility / state ----------
    property bool visible_: false
    property string query: ""
    property int selectedIndex: 0
    property var apps: []
    property bool appsLoaded: false
    // Active drill-down. "" means root (category navigators + everything
    // searchable); any other value pins the list to that category. Set by
    // activating a category nav row; cleared by Esc / Backspace-on-empty.
    property string categoryFilter: ""

    // File-search reuses the category-drill machinery: the Files nav row
    // sets categoryFilter to this sentinel, filteredItems pivots to fd
    // results, and goUp/Esc unwind via the same path as any other category.
    readonly property string fileCategory: "Files"
    readonly property bool fileMode: root.categoryFilter === root.fileCategory

    readonly property string sectionIcon: {
        if (root.categoryFilter === "") return "";
        for (let i = 0; i < root.categoryNav.length; i++) {
            if (root.categoryNav[i].target === root.categoryFilter)
                return root.categoryNav[i].icon;
        }
        return "";
    }

    property var fileItems: []
    readonly property bool fdRunning: fdProc.running

    property string previewPath: ""
    property string previewText: ""
    property string previewMeta: ""
    readonly property string previewKind: {
        if (!root.previewPath) return "";
        const ext = root.fileExt(root.previewPath);
        if (root.imageExts.indexOf(ext) >= 0) return "image";
        if (root.textExts.indexOf(ext) >= 0) return "text";
        return "meta";
    }

    readonly property string homeDir: Quickshell.env("HOME")

    // fd already respects .gitignore, the global ignore file, and skips
    // hidden files by default. These excludes catch build dirs that
    // aren't always gitignored.
    readonly property var fdExcludes: [
        "node_modules", "target", "dist", "build", ".cache",
        ".venv", "__pycache__", ".tox", ".next", ".nuxt"
    ]

    readonly property var imageExts: [
        "png", "jpg", "jpeg", "webp", "gif", "bmp", "ico", "avif", "svg"
    ]

    readonly property var textExts: [
        "md", "txt", "qml", "lua", "toml", "sh", "bash", "zsh", "fish",
        "py", "js", "mjs", "cjs", "ts", "tsx", "jsx", "json", "jsonc",
        "yaml", "yml", "rs", "go", "c", "h", "cpp", "hpp", "cc", "hh",
        "html", "css", "scss", "conf", "ini", "cfg", "log", "csv", "xml",
        "rb", "java", "kt", "swift", "php", "sql", "vim", "el", "tex",
        "gitignore", "gitconfig", "dockerfile", "makefile", "env"
    ]

    readonly property var fileIcons: ({
        "png": "󰋩", "jpg": "󰋩", "jpeg": "󰋩", "webp": "󰋩", "gif": "󰋩",
        "bmp": "󰋩", "ico": "󰋩", "avif": "󰋩", "svg": "󰜡", "tiff": "󰋩",
        "mp4": "󰕧", "mkv": "󰕧", "webm": "󰕧", "mov": "󰕧", "avi": "󰕧",
        "m4v": "󰕧", "flv": "󰕧",
        "mp3": "󰝚", "flac": "󰝚", "ogg": "󰝚", "wav": "󰝚", "m4a": "󰝚",
        "opus": "󰝚", "aac": "󰝚",
        "pdf": "󰈦", "epub": "󰂺", "djvu": "󰈦",
        "doc": "󰈬", "docx": "󰈬", "odt": "󰈬", "rtf": "󰈬",
        "xls": "󰈛", "xlsx": "󰈛", "ods": "󰈛",
        "ppt": "󰈧", "pptx": "󰈧", "odp": "󰈧",
        "zip": "󰗄", "tar": "󰗄", "gz": "󰗄", "xz": "󰗄", "bz2": "󰗄",
        "7z": "󰗄", "rar": "󰗄", "zst": "󰗄",
        "md": "󰍔", "txt": "󰈙", "log": "󰦪", "csv": "󰈛",
        "json": "󰘦", "jsonc": "󰘦", "yaml": "󰈙", "yml": "󰈙",
        "toml": "󰈙", "xml": "󰗀", "ini": "󰒓", "cfg": "󰒓",
        "conf": "󰒓", "env": "󰒓",
        "sh": "󱆃", "bash": "󱆃", "zsh": "󱆃", "fish": "󰈺",
        "lua": "󰢱", "vim": "",
        "html": "󰌝", "css": "󰌜", "scss": "󰌜", "sass": "󰌜",
        "py": "󰌠", "js": "󰌞", "mjs": "󰌞", "cjs": "󰌞",
        "ts": "󰛦", "tsx": "󰜈", "jsx": "󰜈",
        "rs": "󱘗", "go": "󰟓", "java": "󰬷", "kt": "󱈙",
        "swift": "󰛥", "rb": "󰴭", "php": "󰌟",
        "c": "󰙱", "h": "󰙱", "cpp": "󰙲", "hpp": "󰙲", "cc": "󰙲", "hh": "󰙲",
        "qml": "󰢫", "sql": "󰆼", "el": "", "tex": "",
        // Dotless filenames: fileExt() returns the whole lowercased name.
        "gitignore": "", "gitconfig": "",
        "dockerfile": "󰡨", "makefile": "󰣪"
    })

    function fileIcon(path) {
        const ext = root.fileExt(path);
        return root.fileIcons[ext] || "";
    }

    function open() {
        root.query = "";
        root.selectedIndex = 0;
        root.categoryFilter = "";
        root.visible_ = true;
    }
    function close() { root.visible_ = false; }
    function toggle() { if (root.visible_) close(); else open(); }
    function goUp() {
        // Step back one level. At root this is a no-op so the caller can
        // chain "goUp or close" without a branch.
        if (root.categoryFilter !== "") {
            root.categoryFilter = "";
            root.query = "";
            root.selectedIndex = 0;
            return true;
        }
        return false;
    }

    // Entering or leaving file mode resets fd state. Other category drills
    // share the same handler — clearing fileItems for them is a free no-op.
    onCategoryFilterChanged: {
        root.fileItems = [];
        root.previewPath = "";
        root.previewText = "";
        root.previewMeta = "";
        fdDebounce.stop();
    }

    // ---------- Palette loader ----------
    function parseColors(text) {
        const want = { background: null, foreground: null, accent: null,
                       color1: null, color7: null, color8: null };
        const re = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]+)"/;
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const m = lines[i].match(re);
            if (m && (m[1] in want)) want[m[1]] = m[2];
        }
        if (want.background) root.paper   = want.background;
        if (want.foreground) root.ink     = want.foreground;
        if (want.color7)     root.inkDeep = want.color7;
        if (want.color8)     root.sumi    = want.color8;
        if (want.accent)     root.indigo  = want.accent;
        if (want.color1)     root.seal    = want.color1;
    }
    FileView {
        id: paletteFile
        path: root.colorsPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parseColors(paletteFile.text())
    }

    // omarchy-theme-set rm -rf's current/theme/ and mv's a fresh dir in, so
    // colors.toml gets a new inode each swap and paletteFile's inotify watch
    // dies with it. theme.name, by contrast, is rewritten in place so its
    // inode is stable. Use it as a swap-detection beacon and re-arm
    // paletteFile.
    FileView {
        id: themeMarker
        path: root.themeNamePath
        watchChanges: true
        onFileChanged: { reload(); paletteFile.reload(); }
    }

    // ---------- Static omarchy-menu items ----------
    // Every leaf action `omarchy-menu` can dispatch is flattened here with a
    // synonym list so search hits non-obvious terms. `exec` is the bash run
    // verbatim; for items that drop into walker submenus we shell out to
    // `omarchy-menu <verb>` and let the existing dmenu UX take it from there.
    readonly property var omarchyItems: [
        // ----- Style -----
        // Picker items delegate to `omarchy-menu <verb>` — those that
        // accept the verb directly (theme, background, about) jump to a
        // single-step walker picker; the rest (Font, Waybar Position,
        // Corners, Screensaver) route to `omarchy-menu style` and need one
        // extra click. Matches the bash menu's actual reachable surface;
        // see go_to_menu() in omarchy-menu for the verb list.
        { title: "Theme",            icon: "󰸌", category: "Style",   keywords: "theme color palette dark light mode appearance look style scheme switcher kanagawa tokyo dragon nord gruvbox", exec: "omarchy-menu theme" },
        { title: "Background",       icon: "󰸉",  category: "Style",   keywords: "background wallpaper image desktop picture backdrop bg",                                                 exec: "omarchy-menu background" },
        { title: "Font",             icon: "󰛖",  category: "Style",   keywords: "font typeface monospace typography family character glyph nerd",                                        exec: "omarchy-menu style" },
        { title: "Waybar Position",  icon: "󰍜", category: "Style",   keywords: "bar panel top bottom left right position dock waybar status",                                          exec: "omarchy-menu style" },
        { title: "Corners",          icon: "󰘇", category: "Style",   keywords: "corners radius round sharp border edge shape window",                                                  exec: "omarchy-menu style" },
        { title: "Hyprland Look",    icon: "󰕮",  category: "Style",   keywords: "hyprland looknfeel border gaps animation effects compositor window",                                   exec: "omarchy-launch-editor ~/.config/hypr/looknfeel.lua" },
        { title: "Screensaver",      icon: "󱄄", category: "Style",   keywords: "screensaver branding lock idle screen saver text image logo",                                        exec: "omarchy-menu style" },
        { title: "About",            icon: "󰋽",  category: "Style",   keywords: "about branding logo profile text image owner identity",                                                exec: "omarchy-menu about" },
        { title: "Unlock Theme",     icon: "󰟵", category: "Style",   keywords: "unlock premium paid theme purchase license",                                                          exec: "omarchy-launch-walker -m menus:omarchyunlocks --width 800 --minheight 400" },

        // ----- Setup -----
        { title: "Audio",            icon: "󰕾",  category: "Setup",   keywords: "audio sound speaker mixer pulse pipewire volume output input device",                                  exec: "omarchy-launch-audio" },
        { title: "Wi-Fi",            icon: "󰖩",  category: "Setup",   keywords: "wifi wireless network internet nmcli connection",                                                      exec: "omarchy-launch-wifi" },
        { title: "Bluetooth",        icon: "󰂯", category: "Setup",   keywords: "bluetooth bt pair device headset speaker keyboard mouse",                                              exec: "omarchy-launch-bluetooth" },
        { title: "Power Profile",    icon: "󱐋", category: "Setup",   keywords: "power profile performance battery saver balanced cpu governor",                                       exec: "omarchy-menu power" },
        { title: "System Sleep",     icon: "󰤄",  category: "Setup",   keywords: "sleep suspend hibernate power management lid",                                                         exec: "omarchy-menu setup" },
        { title: "Monitors",         icon: "󰍹", category: "Setup",   keywords: "monitor display screen resolution scaling refresh hz external hdmi displayport",                       exec: "omarchy-launch-editor ~/.config/hypr/monitors.lua" },
        { title: "Keybindings",      icon: "󰌌",  category: "Setup",   keywords: "keybindings shortcuts hotkeys keymap bindings input hypr",                                              exec: "omarchy-launch-editor ~/.config/hypr/bindings.lua" },
        { title: "Input",            icon: "󰍽",  category: "Setup",   keywords: "input keyboard mouse touchpad layout language repeat",                                                 exec: "omarchy-launch-editor ~/.config/hypr/input.lua" },
        { title: "Default Browser",  icon: "󰖟",  category: "Setup",   keywords: "default browser web chrome firefox brave edge zen chromium",                                           exec: "omarchy-menu setup" },
        { title: "Default Terminal", icon: "󰆍",  category: "Setup",   keywords: "default terminal alacritty foot ghostty kitty emulator shell",                                          exec: "omarchy-menu setup" },
        { title: "Default Editor",   icon: "󱩼",  category: "Setup",   keywords: "default editor neovim vscode cursor zed sublime helix vim emacs ide",                                  exec: "omarchy-menu setup" },
        { title: "DNS",              icon: "󰱔", category: "Setup",   keywords: "dns resolver network domain server nameserver",                                                       exec: "omarchy-setup-dns",                  tui: "omarchy-launch-floating-terminal-with-presentation" },
        { title: "Fingerprint",      icon: "󰈷", category: "Setup",   keywords: "fingerprint biometric security login auth fingerprint reader",                                         exec: "omarchy-setup-security-fingerprint", tui: "omarchy-launch-floating-terminal-with-presentation" },
        { title: "Fido2 Key",        icon: "󰌆",  category: "Setup",   keywords: "fido2 yubikey hardware key security 2fa auth",                                                          exec: "omarchy-setup-security-fido2",       tui: "omarchy-launch-floating-terminal-with-presentation" },
        { title: "Hyprland Config",  icon: "󰢨",  category: "Setup",   keywords: "hyprland config compositor window manager edit settings",                                              exec: "omarchy-launch-editor ~/.config/hypr/hyprland.lua" },
        { title: "Hypridle Config",  icon: "󱎫",  category: "Setup",   keywords: "hypridle idle timeout lock screen blank afk",                                                          exec: "omarchy-launch-editor ~/.config/hypr/hypridle.conf" },
        { title: "Hyprlock Config",  icon: "󰌾",  category: "Setup",   keywords: "hyprlock lock screen password security",                                                                exec: "omarchy-launch-editor ~/.config/hypr/hyprlock.conf" },
        { title: "Hyprsunset Config",icon: "󰖕",  category: "Setup",   keywords: "hyprsunset nightlight blue light filter warm temperature",                                              exec: "omarchy-launch-editor ~/.config/hypr/hyprsunset.conf" },
        { title: "Plymouth",         icon: "󱣴", category: "Setup",   keywords: "plymouth boot splash screen logo",                                                                     exec: "omarchy-refresh-plymouth" },
        { title: "Swayosd Config",   icon: "󰧴",  category: "Setup",   keywords: "swayosd osd volume brightness indicator overlay",                                                       exec: "omarchy-launch-editor ~/.config/swayosd/config.toml" },
        { title: "Walker Config",    icon: "󰌧", category: "Setup",   keywords: "walker launcher runner dmenu picker rofi",                                                              exec: "omarchy-launch-editor ~/.config/walker/config.toml" },
        { title: "Waybar Config",    icon: "󰍜", category: "Setup",   keywords: "waybar status bar config modules",                                                                      exec: "omarchy-launch-editor ~/.config/waybar/config.jsonc" },
        { title: "XCompose",         icon: "󰞅", category: "Setup",   keywords: "xcompose compose key special characters accents typing emoji input",                                  exec: "omarchy-launch-editor ~/.XCompose" },

        // ----- Install -----
        { title: "Install Package",       icon: "󰣇", category: "Install", keywords: "install package pacman pkg arch repo add",                                  exec: "omarchy-pkg-install",          tui: "omarchy-launch-tui" },
        { title: "Install from AUR",      icon: "󰣇", category: "Install", keywords: "aur install package yay paru arch user repository",                          exec: "omarchy-pkg-aur-install",      tui: "omarchy-launch-tui" },
        { title: "Install Web App",       icon: "󱂛",  category: "Install", keywords: "web app pwa browser shortcut install chromium edge",                          exec: "omarchy-webapp-install",       tui: "omarchy-launch-floating-terminal-with-presentation" },
        { title: "Install TUI",           icon: "󰆍",  category: "Install", keywords: "tui terminal app cli tool install",                                            exec: "omarchy-tui-install",          tui: "omarchy-launch-floating-terminal-with-presentation" },
        { title: "Install Service",       icon: "󰒋",  category: "Install", keywords: "service install dropbox tailscale nordvpn vpn sunshine bitwarden",            exec: "omarchy-menu install service" },
        { title: "Install Style",         icon: "󰏘",  category: "Install", keywords: "install style theme background font palette appearance",                       exec: "omarchy-menu install style" },
        { title: "Install Theme",         icon: "󰸌", category: "Install", keywords: "install theme color palette appearance download",                              exec: "omarchy-theme-install",        tui: "omarchy-launch-floating-terminal-with-presentation" },
        { title: "Install Background",    icon: "󰸉",  category: "Install", keywords: "install background wallpaper image download add",                              exec: "omarchy-theme-bg-install" },
        { title: "Install Dev Env",       icon: "󰵮", category: "Install", keywords: "development install ruby rails javascript node go php python elixir zig rust java dotnet ocaml clojure scala", exec: "omarchy-menu install development" },
        { title: "Install Editor",        icon: "󱩼",  category: "Install", keywords: "editor install vscode cursor zed sublime helix vim emacs neovim ide",          exec: "omarchy-menu install editor" },
        { title: "Install Terminal",      icon: "󰆍",  category: "Install", keywords: "terminal install alacritty foot ghostty kitty",                                exec: "omarchy-menu install terminal" },
        { title: "Install Browser",       icon: "󰖟",  category: "Install", keywords: "browser install chrome edge brave firefox zen chromium web",                   exec: "omarchy-menu install browser" },
        { title: "Install AI",            icon: "󱚤", category: "Install", keywords: "ai install ollama lmstudio crush dictation voice llm gpt local",              exec: "omarchy-menu install ai" },
        { title: "Install Gaming",        icon: "󰊴",  category: "Install", keywords: "gaming install steam retroarch minecraft geforce xbox moonlight lutris heroic", exec: "omarchy-menu install gaming" },
        { title: "Install Docker DB",     icon: "󰡨",  category: "Install", keywords: "docker database postgres mysql redis container",                                exec: "omarchy-install-docker-dbs",   tui: "omarchy-launch-floating-terminal-with-presentation" },
        { title: "Install Windows VM",    icon: "󰍲", category: "Install", keywords: "windows vm virtual machine qemu kvm install",                                  exec: "omarchy-windows-vm install",   tui: "omarchy-launch-floating-terminal-with-presentation" },

        // ----- Remove -----
        { title: "Remove Package",        icon: "󰣇", category: "Remove",  keywords: "remove uninstall package pacman arch delete pkg",            exec: "omarchy-pkg-remove",          tui: "omarchy-launch-tui" },
        { title: "Remove Web App",        icon: "󱂛",  category: "Remove",  keywords: "remove web app pwa uninstall",                                exec: "omarchy-webapp-remove",       tui: "omarchy-launch-floating-terminal-with-presentation" },
        { title: "Remove TUI",            icon: "󰆍",  category: "Remove",  keywords: "tui remove uninstall cli tool",                               exec: "omarchy-tui-remove",          tui: "omarchy-launch-floating-terminal-with-presentation" },
        { title: "Remove Theme",          icon: "󰸌", category: "Remove",  keywords: "theme remove uninstall delete palette",                       exec: "omarchy-theme-remove",        tui: "omarchy-launch-floating-terminal-with-presentation" },
        { title: "Remove Dictation",      icon: "󰍬",  category: "Remove",  keywords: "dictation voxtype voice remove uninstall speech",             exec: "omarchy-voxtype-remove",      tui: "omarchy-launch-floating-terminal-with-presentation" },
        { title: "Remove Browser",        icon: "󰖟",  category: "Remove",  keywords: "browser remove uninstall chrome firefox brave edge",          exec: "omarchy-menu remove browser" },
        { title: "Remove Gaming",         icon: "󰊴",  category: "Remove",  keywords: "gaming remove uninstall steam retroarch minecraft",           exec: "omarchy-menu remove gaming" },
        { title: "Remove Dev Env",        icon: "󰵮", category: "Remove",  keywords: "development remove uninstall ruby node go python rust",       exec: "omarchy-menu remove development" },
        { title: "Remove Preinstalls",    icon: "󰏓", category: "Remove",  keywords: "preinstalls remove cleanup bloat default apps",               exec: "omarchy-remove-preinstalls",  tui: "omarchy-launch-floating-terminal-with-presentation" },
        { title: "Remove Windows VM",     icon: "󰍲", category: "Remove",  keywords: "windows vm virtual machine remove uninstall",                 exec: "omarchy-windows-vm remove",   tui: "omarchy-launch-floating-terminal-with-presentation" },

        // ----- Update -----
        { title: "Update Omarchy",        icon: "󰦗",  category: "Update",  keywords: "update upgrade omarchy system latest sync pull",                        exec: "omarchy-update",              tui: "omarchy-launch-floating-terminal-with-presentation" },
        { title: "Update Channel",        icon: "󰔫", category: "Update",  keywords: "channel branch stable rc edge dev release track",                        exec: "omarchy-menu update" },
        { title: "Update Themes",         icon: "󰸌", category: "Update",  keywords: "themes update refresh extra catalogue",                                  exec: "omarchy-theme-update",        tui: "omarchy-launch-floating-terminal-with-presentation" },
        { title: "Update Firmware",       icon: "󰍛",  category: "Update",  keywords: "firmware bios uefi fwupd update flash",                                  exec: "omarchy-update-firmware",     tui: "omarchy-launch-floating-terminal-with-presentation" },
        { title: "Update Time",           icon: "󰥔",  category: "Update",  keywords: "time ntp sync clock update",                                              exec: "omarchy-update-time",         tui: "omarchy-launch-floating-terminal-with-presentation" },
        { title: "Update Timezone",       icon: "󰃭",  category: "Update",  keywords: "timezone tz region locale time zone change",                              exec: "omarchy-tz-select",           tui: "omarchy-launch-floating-terminal-with-presentation" },
        { title: "Update Drive Password", icon: "󰋊",  category: "Update",  keywords: "drive password luks encryption disk security",                            exec: "omarchy-drive-password",      tui: "omarchy-launch-floating-terminal-with-presentation" },
        { title: "Update User Password",  icon: "󰷛",  category: "Update",  keywords: "user password passwd security login change",                              exec: "passwd",                      tui: "omarchy-launch-floating-terminal-with-presentation" },
        { title: "Reset Hyprland Config", icon: "󰑐",  category: "Update",  keywords: "reset default config hyprland restore factory refresh",                  exec: "omarchy-refresh-hyprland" },
        { title: "Reset Hypridle Config", icon: "󰑐",  category: "Update",  keywords: "reset default config hypridle idle restore",                              exec: "omarchy-refresh-hypridle" },
        { title: "Reset Hyprlock Config", icon: "󰑐",  category: "Update",  keywords: "reset default config hyprlock lock restore",                              exec: "omarchy-refresh-hyprlock" },
        { title: "Reset Hyprsunset Cfg",  icon: "󰑐",  category: "Update",  keywords: "reset default config hyprsunset nightlight restore",                      exec: "omarchy-refresh-hyprsunset" },
        { title: "Reset Swayosd Config",  icon: "󰑐",  category: "Update",  keywords: "reset default config swayosd osd restore",                                exec: "omarchy-refresh-swayosd" },
        { title: "Reset Tmux Config",     icon: "󰑐",  category: "Update",  keywords: "reset default config tmux restore",                                       exec: "omarchy-refresh-tmux" },
        { title: "Reset Walker Config",   icon: "󰌧", category: "Update",  keywords: "reset default config walker launcher restore",                            exec: "omarchy-refresh-walker" },
        { title: "Reset Waybar Config",   icon: "󰍜", category: "Update",  keywords: "reset default config waybar bar restore",                                 exec: "omarchy-refresh-waybar" },
        { title: "Restart Hypridle",      icon: "󰜉",  category: "Update",  keywords: "restart hypridle idle service process reload",                            exec: "omarchy-restart-hypridle" },
        { title: "Restart Hyprsunset",    icon: "󰜉",  category: "Update",  keywords: "restart hyprsunset nightlight service process reload",                    exec: "omarchy-restart-hyprsunset" },
        { title: "Restart Mako",          icon: "󰎟", category: "Update",  keywords: "restart mako notifications dunst service reload",                         exec: "omarchy-restart-mako" },
        { title: "Restart Swayosd",       icon: "󰜉",  category: "Update",  keywords: "restart swayosd osd service reload",                                      exec: "omarchy-restart-swayosd" },
        { title: "Restart Walker",        icon: "󰌧", category: "Update",  keywords: "restart walker launcher service reload",                                  exec: "omarchy-restart-walker" },
        { title: "Restart Waybar",        icon: "󰍜", category: "Update",  keywords: "restart waybar bar service reload",                                       exec: "omarchy-restart-waybar" },
        { title: "Restart Audio",         icon: "󰜉",  category: "Update",  keywords: "restart audio pipewire pulse sound reload service",                       exec: "omarchy-restart-pipewire" },
        { title: "Restart Wi-Fi",         icon: "󱚾", category: "Update",  keywords: "restart wifi wireless network reload service",                            exec: "omarchy-restart-wifi" },
        { title: "Restart Bluetooth",     icon: "󰂯", category: "Update",  keywords: "restart bluetooth bt reload service",                                     exec: "omarchy-restart-bluetooth" },
        { title: "Restart Trackpad",      icon: "󰟸", category: "Update",  keywords: "restart trackpad touchpad pointer reload service",                        exec: "omarchy-restart-trackpad" },

        // ----- System -----
        { title: "Lock Screen",         icon: "󰌾", category: "System", keywords: "lock screen security hyprlock password",                                            exec: "omarchy-system-lock" },
        { title: "Force Screensaver",   icon: "󱄄", category: "System", keywords: "screensaver force start show idle",                                              exec: "omarchy-launch-screensaver force" },
        { title: "Suspend",             icon: "󰒲", category: "System", keywords: "suspend sleep power down ram s3",                                                 exec: "systemctl suspend" },
        { title: "Hibernate",           icon: "󰤁", category: "System", keywords: "hibernate disk power down s4 swap",                                               exec: "systemctl hibernate" },
        { title: "Logout",              icon: "󰍃", category: "System", keywords: "logout signout exit session end",                                                  exec: "omarchy-system-logout" },
        { title: "Restart Computer",    icon: "󰜉", category: "System", keywords: "restart reboot reset power cycle",                                                exec: "omarchy-system-reboot" },
        { title: "Shutdown",            icon: "󰐥", category: "System", keywords: "shutdown poweroff off halt turn off",                                              exec: "omarchy-system-shutdown" },

        // ----- Toggle -----
        { title: "Toggle Screensaver",  icon: "󱄄", category: "Toggle", keywords: "toggle screensaver enable disable on off",                                        exec: "omarchy-toggle-screensaver" },
        { title: "Toggle Nightlight",   icon: "󰔎", category: "Toggle", keywords: "toggle nightlight blue light filter warm color temperature hyprsunset",            exec: "omarchy-toggle-nightlight" },
        { title: "Toggle Idle Lock",    icon: "󱫖", category: "Toggle", keywords: "toggle idle lock auto away timeout",                                                exec: "omarchy-toggle-idle" },
        { title: "Toggle Notifications",icon: "󰂛", category: "Toggle", keywords: "toggle notifications silence mute mako dnd",                                       exec: "omarchy-toggle-notification-silencing" },
        { title: "Toggle Top Bar",      icon: "󰍜", category: "Toggle", keywords: "toggle waybar top bar show hide visibility",                                       exec: "omarchy-toggle-waybar" },
        { title: "Toggle Workspace Layout", icon: "󱂬", category: "Toggle", keywords: "toggle workspace layout dwindle master tile hyprland",                          exec: "omarchy-hyprland-workspace-layout-toggle" },
        { title: "Toggle Window Gaps",  icon: "󱂩",  category: "Toggle", keywords: "toggle gaps window spacing hyprland margin",                                       exec: "omarchy-hyprland-window-gaps-toggle" },
        { title: "Toggle 1-Window Ratio",icon: "󰋃", category: "Toggle", keywords: "toggle aspect ratio single window square",                                          exec: "omarchy-hyprland-window-single-square-aspect-toggle" },
        { title: "Toggle Monitor Scaling", icon: "󰍹", category: "Toggle", keywords: "toggle monitor scaling cycle resolution hidpi",                                  exec: "omarchy-hyprland-monitor-scaling-cycle" },
        { title: "Toggle Direct Boot",  icon: "󰓅",  category: "Toggle", keywords: "toggle direct boot autologin no password",                                          exec: "omarchy-config-direct-boot", tui: "omarchy-launch-floating-terminal-with-presentation" },
        { title: "Toggle Passwordless Sudo", icon: "󰟵", category: "Toggle", keywords: "passwordless sudo nopasswd root admin security",                               exec: "omarchy-sudo-passwordless",  tui: "omarchy-launch-floating-terminal-with-presentation" },
        { title: "Toggle Suspend",      icon: "󰒲", category: "Toggle", keywords: "toggle suspend disable enable sleep power",                                        exec: "omarchy-toggle-suspend" },
        { title: "Toggle Touchpad",     icon: "󰟸", category: "Toggle", keywords: "toggle touchpad trackpad enable disable",                                          exec: "omarchy-toggle-touchpad" },
        { title: "Toggle Touchscreen",  icon: "󰆽", category: "Toggle", keywords: "toggle touchscreen enable disable",                                                exec: "omarchy-toggle-touchscreen" },

        // ----- Capture -----
        { title: "Screenshot",          icon: "󰄀",  category: "Capture", keywords: "screenshot screen capture image png shot snip print",                              exec: "omarchy-capture-screenshot" },
        { title: "Screen Record",       icon: "󰑊",  category: "Capture", keywords: "screen record video capture mp4 gif",                                              exec: "omarchy-capture-screenrecording" },
        { title: "Text Extraction (OCR)",icon: "󰴑", category: "Capture", keywords: "ocr text extract recognize image scan copy",                                       exec: "omarchy-capture-text-extraction" },
        { title: "Color Picker",        icon: "󰃉", category: "Capture", keywords: "color picker hex rgb hyprpicker dropper sample eyedropper",                        exec: "bash -c 'pkill hyprpicker || hyprpicker -a'" },

        // ----- Share -----
        { title: "Share Clipboard",     icon: "󰅎",  category: "Share",   keywords: "share clipboard localsend send transfer",                                          exec: "omarchy-menu-share clipboard" },
        { title: "Share File",          icon: "󰈤",  category: "Share",   keywords: "share file send transfer localsend",                                                exec: "omarchy-menu-share file",   tui: "omarchy-launch-tui" },
        { title: "Share Folder",        icon: "󰉒",  category: "Share",   keywords: "share folder directory send transfer localsend",                                    exec: "omarchy-menu-share folder", tui: "omarchy-launch-tui" },
        { title: "Receive (LocalSend)", icon: "󰥦", category: "Share",   keywords: "receive localsend share airdrop transfer",                                          exec: "uwsm-app -- localsend" },

        // ----- Trigger -----
        { title: "Set Reminder",        icon: "󰔛", category: "Trigger", keywords: "reminder alarm timer notify wake notification",                                    exec: "omarchy-menu reminder-set" },
        { title: "Show Reminders",      icon: "󰔛", category: "Trigger", keywords: "reminders show list pending",                                                       exec: "omarchy-reminder show" },
        { title: "Clear Reminders",     icon: "󰔛", category: "Trigger", keywords: "reminders clear delete remove all",                                                 exec: "omarchy-reminder clear" },
        { title: "Transcode Media",     icon: "󰧸", category: "Trigger", keywords: "transcode media video audio convert compress mp4 mp3",                              exec: "omarchy-transcode" },

        // ----- Learn -----
        { title: "Keybindings",         icon: "󰌌",  category: "Learn", keywords: "keybindings shortcuts hotkeys cheatsheet reference help",                              exec: "omarchy-menu-keybindings" },
        { title: "Tmux Keybindings",    icon: "󱂬",  category: "Learn", keywords: "tmux keybindings shortcuts reference",                                                 exec: "omarchy-menu-tmux-keybindings" },
        { title: "Omarchy Manual",      icon: "󰂺",  category: "Learn", keywords: "omarchy manual docs documentation help learn",                                         exec: "omarchy-launch-webapp 'https://learn.omacom.io/2/the-omarchy-manual'" },
        { title: "Hyprland Wiki",       icon: "󱁉",  category: "Learn", keywords: "hyprland wiki docs documentation help",                                                exec: "omarchy-launch-webapp 'https://wiki.hypr.land/'" },
        { title: "Arch Wiki",           icon: "󰣇", category: "Learn", keywords: "arch wiki docs documentation help linux",                                              exec: "omarchy-launch-webapp 'https://wiki.archlinux.org/title/Main_page'" },
        { title: "Neovim Keymaps",      icon: "󰕷",  category: "Learn", keywords: "neovim nvim keymaps shortcuts lazyvim reference",                                      exec: "omarchy-launch-webapp 'https://www.lazyvim.org/keymaps'" },
        { title: "Bash Cheatsheet",     icon: "󱆃", category: "Learn", keywords: "bash shell cheatsheet reference scripting",                                            exec: "omarchy-launch-webapp 'https://devhints.io/bash'" }
    ]

    // ---------- Desktop file scan ----------
    // configparser handles the gnarly bits — section headers, continuation
    // lines, encodings, comments, mixed quoting. One spawn at startup; the
    // result is cached for the session and refreshed only via IPC.
    Process {
        id: appScan
        running: false
        command: ["python3", "-c", "import os, glob, re, configparser, sys\n" +
            "dirs = [\n" +
            "    os.path.expanduser('~/.local/share/applications'),\n" +
            "    '/usr/share/applications',\n" +
            "    '/var/lib/flatpak/exports/share/applications',\n" +
            "    os.path.expanduser('~/.local/share/flatpak/exports/share/applications'),\n" +
            "    '/var/lib/snapd/desktop/applications',\n" +
            "]\n" +
            "rx = re.compile(r'%[fFuUdDnNickvm]')\n" +
            "seen = set()\n" +
            "out = []\n" +
            "for d in dirs:\n" +
            "    if not os.path.isdir(d):\n" +
            "        continue\n" +
            "    for f in sorted(glob.glob(os.path.join(d, '*.desktop'))):\n" +
            "        cp = configparser.RawConfigParser(strict=False, interpolation=None)\n" +
            "        try:\n" +
            "            cp.read(f, encoding='utf-8')\n" +
            "        except Exception:\n" +
            "            continue\n" +
            "        if 'Desktop Entry' not in cp:\n" +
            "            continue\n" +
            "        de = cp['Desktop Entry']\n" +
            "        if de.get('NoDisplay', '').lower() == 'true':\n" +
            "            continue\n" +
            "        if de.get('Hidden', '').lower() == 'true':\n" +
            "            continue\n" +
            "        if de.get('Type', 'Application').strip() != 'Application':\n" +
            "            continue\n" +
            "        name = de.get('Name', '').strip()\n" +
            "        if not name:\n" +
            "            continue\n" +
            "        key = name.lower()\n" +
            "        if key in seen:\n" +
            "            continue\n" +
            "        seen.add(key)\n" +
            "        comment = de.get('Comment', '').strip()\n" +
            "        keywords = de.get('Keywords', '').strip().replace(';', ' ')\n" +
            "        categories = de.get('Categories', '').strip().replace(';', ' ')\n" +
            "        exe = rx.sub('', de.get('Exec', '').strip()).strip()\n" +
            "        if not exe:\n" +
            "            continue\n" +
            "        icon = de.get('Icon', '').strip()\n" +
            "        gname = de.get('GenericName', '').strip()\n" +
            "        def s(x):\n" +
            "            return x.replace('\\t', ' ').replace('\\n', ' ').replace('\\r', ' ')\n" +
            "        out.append('\\t'.join([s(name), s(comment), s(keywords), s(categories), s(exe), s(icon), s(gname)]))\n" +
            "sys.stdout.write('\\n'.join(out))\n"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n").filter(s => s.length > 0);
                const apps = new Array(lines.length);
                let n = 0;
                for (let i = 0; i < lines.length; i++) {
                    const p = lines[i].split("\t");
                    if (p.length < 7) continue;
                    apps[n++] = {
                        title: p[0],
                        comment: p[1],
                        keywords: (p[2] + " " + p[3] + " " + p[6] + " " + p[1]).toLowerCase(),
                        category: "App",
                        icon: "󰀻",
                        exec: p[4],
                        rawIcon: p[5]
                    };
                }
                apps.length = n;
                const annotated = root.annotate(apps);
                root.apps = annotated;
                root.allItems = root.omarchy.concat(annotated);
                root.appsLoaded = true;
            }
        }
    }

    // ---------- Category navigators ----------
    // Synthetic rows that appear at root level. Activating one filters the
    // list to that category instead of executing a command. `target` is the
    // category string to match; "App" is the bucket all .desktop entries
    // land in.
    readonly property var categoryNav: [
        { title: "Apps",    icon: "󰀻", category: "Browse", isCategory: true, target: "App",     keywords: "apps applications launcher programs software desktop" },
        { title: "Files",   icon: "󰉋", category: "Browse", isCategory: true, target: root.fileCategory, keywords: "files file search find folder browse path open image picture document text fd" },
        { title: "Style",   icon: "󰏘", category: "Browse", isCategory: true, target: "Style",   keywords: "style theme appearance look font background corners waybar screensaver" },
        { title: "Setup",   icon: "󰒓", category: "Browse", isCategory: true, target: "Setup",   keywords: "setup config audio wifi bluetooth power monitors keybindings defaults dns security" },
        { title: "Install", icon: "󰏗", category: "Browse", isCategory: true, target: "Install", keywords: "install add package aur webapp tui service style dev editor terminal browser ai gaming" },
        { title: "Remove",  icon: "󰆴", category: "Browse", isCategory: true, target: "Remove",  keywords: "remove uninstall delete package webapp tui theme browser gaming dev preinstalls" },
        { title: "Update",  icon: "󰚰", category: "Browse", isCategory: true, target: "Update",  keywords: "update upgrade omarchy channel themes process hardware firmware password timezone time" },
        { title: "System",  icon: "󰐥", category: "Browse", isCategory: true, target: "System",  keywords: "system lock suspend hibernate logout restart reboot shutdown power" },
        { title: "Toggle",  icon: "󰨚", category: "Browse", isCategory: true, target: "Toggle",  keywords: "toggle screensaver nightlight idle notifications bar layout gaps scaling sudo touchpad" },
        { title: "Trigger", icon: "󰚥", category: "Browse", isCategory: true, target: "Trigger", keywords: "trigger reminder transcode capture share toggle hardware" },
        { title: "Capture", icon: "󰄀", category: "Browse", isCategory: true, target: "Capture", keywords: "capture screenshot screenrecord ocr text extraction color picker" },
        { title: "Share",   icon: "󰒖", category: "Browse", isCategory: true, target: "Share",   keywords: "share clipboard file folder receive localsend send transfer" },
        { title: "Learn",   icon: "󰂺", category: "Browse", isCategory: true, target: "Learn",   keywords: "learn docs manual help keybindings wiki cheatsheet" }
    ]

    // ---------- Icon resolution ----------
    // `.desktop` Icon field is either an absolute path or an icon-theme
    // name. Qt's QQmlEngine doesn't know about XDG themes, so theme names
    // get pushed through Quickshell.iconPath for resolution; absolute paths
    // just need a file:// prefix. Returns "" when nothing resolves so the
    // delegate can fall back to its nerd-font glyph.
    function resolveIconUrl(raw) {
        if (!raw) return "";
        if (raw.charAt(0) === "/") return "file://" + raw;
        return Quickshell.iconPath(raw, "");
    }

    // ---------- Search index annotation ----------
    // Builds an annotated copy of `items` with lowercased searchable fields
    // attached as `_t/_k/_c`. Done once at startup (and once after the .desktop
    // scan completes) so the per-keystroke scoring loop doesn't lowercase
    // hundreds of strings per character of input.
    function annotate(items) {
        const out = new Array(items.length);
        for (let i = 0; i < items.length; i++) {
            const it = items[i];
            out[i] = Object.assign({}, it, {
                _t: (it.title || "").toLowerCase(),
                _k: (it.keywords || "").toLowerCase(),
                _c: (it.category || "").toLowerCase()
            });
        }
        return out;
    }

    // Annotated indexes. Assigned in Component.onCompleted and in the
    // appScan handler so they stay plain `var` assignments rather than
    // re-evaluating bindings whose dependency graph would re-allocate the
    // 200+ entry array on unrelated property touches.
    property var omarchy: []
    property var nav: []
    property var allItems: []

    // ---------- Launcher ----------
    // Matches omarchy's launch convention (see omarchy-launch-or-focus):
    //   setsid -f          fork into a new session, returning immediately
    //                      so quickshell's Process completes; the spawned
    //                      app fully detaches from quickshell's lifetime
    //   uwsm-app -- <cmd>  registers the spawn under a systemd-user scope
    //                      (omarchy convention; gives the app a managed
    //                      unit, proper cgroup, clean logout teardown)
    //   bash -c "<exec>"   lets exec lines with shell syntax (pipes,
    //                      ||, &&, redirects) work alongside plain
    //                      argv-style commands without a special case
    Process { id: runner; running: false }
    function activate(item) {
        if (!item) return;
        if (item.isCategory) {
            root.categoryFilter = item.target;
            root.query = "";
            root.selectedIndex = 0;
            return;
        }
        // TUI commands need a real terminal — fzf, sudo prompts, and bash
        // `read` fail when launched detached. `item.tui` holds the wrapper
        // command name (omarchy-launch-tui or omarchy-launch-floating-…).
        const cmd = item.tui ? item.tui + " " + item.exec : item.exec;
        runner.command = ["sh", "-c",
                          "setsid -f uwsm-app -- bash -c "
                          + JSON.stringify(cmd)
                          + " >/dev/null 2>&1"];
        runner.running = false;
        runner.running = true;
        root.close();
    }

    // ---------- File search (fd) ----------
    // fd does the heavy lifting: smart-case substring/regex matching,
    // .gitignore + global-ignore awareness, hidden-file skip. We layer on
    // an explicit exclude list for build dirs that aren't always
    // gitignored, scope it to $HOME, and cap results so the list stays
    // snappy on noisy queries.
    function basename(p) {
        const s = p.lastIndexOf("/");
        return s >= 0 ? p.substring(s + 1) : p;
    }
    function dirname(p) {
        const s = p.lastIndexOf("/");
        return s >= 0 ? p.substring(0, s) : "";
    }
    function tildify(p) {
        return (p.indexOf(root.homeDir) === 0)
            ? "~" + p.substring(root.homeDir.length)
            : p;
    }

    function buildFdArgs(tokens) {
        const args = ["--type", "f", "--max-results", "200"];
        const excludes = root.fdExcludes;
        for (let i = 0; i < excludes.length; i++) {
            args.push("--exclude");
            args.push(excludes[i]);
        }
        // Join tokens with `.*` for fzf-style gap matching: "img wall"
        // -> "img.*wall" finds "img-wallpaper.png".
        args.push(tokens.join(".*"));
        args.push(root.homeDir);
        return args;
    }

    Process {
        id: fdProc
        running: false
        command: ["fd"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n").filter(s => s.length > 0);
                const out = new Array(lines.length);
                for (let i = 0; i < lines.length; i++) {
                    const path = lines[i];
                    const dirShort = root.tildify(root.dirname(path));
                    out[i] = {
                        title: root.basename(path),
                        comment: dirShort,
                        keywords: "",
                        category: dirShort,
                        icon: root.fileIcon(path),
                        path: path,
                        exec: "xdg-open " + JSON.stringify(path),
                        isFile: true
                    };
                }
                root.fileItems = out;
                root.selectedIndex = Math.max(0, Math.min(root.selectedIndex,
                                                          out.length - 1));
                root.updatePreview();
            }
        }
    }

    Timer {
        id: fdDebounce
        interval: 120
        repeat: false
        onTriggered: {
            const tokens = root.queryTokens;
            if (!root.fileMode || tokens.length === 0) {
                root.fileItems = [];
                root.updatePreview();
                return;
            }
            fdProc.command = ["fd"].concat(root.buildFdArgs(tokens));
            fdProc.running = false;
            fdProc.running = true;
        }
    }

    // Two Processes so text and metadata sinks can be staged without
    // racing on a shared body property. Each is restarted via running
    // false→true on selection change.
    Process {
        id: textPreviewProc
        running: false
        command: ["true"]
        stdout: StdioCollector {
            onStreamFinished: { root.previewText = this.text; }
        }
    }
    Process {
        id: metaPreviewProc
        running: false
        command: ["true"]
        stdout: StdioCollector {
            onStreamFinished: { root.previewMeta = this.text; }
        }
    }

    function fileExt(path) {
        const name = root.basename(path);
        const dot = name.lastIndexOf(".");
        if (dot <= 0) return name.toLowerCase(); // dotless name (Makefile)
        return name.substring(dot + 1).toLowerCase();
    }

    function updatePreview() {
        const it = root.fileMode ? root.filteredItems[root.selectedIndex] : null;
        const path = (it && it.path) || "";
        if (path === root.previewPath) return;
        root.previewPath = path;
        root.previewText = "";
        root.previewMeta = "";
        if (!path) return;
        const kind = root.previewKind;
        if (kind === "text") {
            root.previewText = "Loading…";
            textPreviewProc.command = ["head", "-c", "8192", path];
            textPreviewProc.running = false;
            textPreviewProc.running = true;
        } else if (kind === "meta") {
            root.previewMeta = "Loading…";
            // Positional $1 keeps the path argv-safe; embedding it in the
            // -c script would let `$`/backticks in filenames expand.
            metaPreviewProc.command = ["sh", "-c",
                "stat -c 'SIZE   %s bytes\nMTIME  %y' \"$1\" 2>/dev/null; "
                + "printf 'MIME   '; file -b --mime-type \"$1\" 2>/dev/null",
                "sh", path];
            metaPreviewProc.running = false;
            metaPreviewProc.running = true;
        }
    }

    onQueryChanged: {
        if (root.fileMode) fdDebounce.restart();
    }
    onSelectedIndexChanged: {
        if (root.fileMode) root.updatePreview();
    }

    // ---------- Search ----------
    // Each query token must match somewhere in the item for the item to
    // qualify; scores stack so "thm dark" finds Theme even though neither
    // token is a prefix on its own. Uses precomputed lowercased fields
    // (`_t`/`_k`/`_c`) so a 200+ item × N-token scoring pass doesn't
    // re-lowercase the same strings on every keystroke.
    function scoreItem(item, tokens) {
        const title = item._t;
        const kw = item._k;
        const cat = item._c;
        let total = 0;
        for (let i = 0; i < tokens.length; i++) {
            const t = tokens[i];
            let sub = 0;
            if (title.indexOf(t) === 0) sub += root.scPrefix;
            else if (title.indexOf(t) >= 0) sub += root.scTitle;
            if (kw.indexOf(t) >= 0) sub += root.scKw;
            if (cat.indexOf(t) >= 0) sub += root.scCat;
            if (sub === 0) return 0; // any token miss disqualifies
            total += sub;
        }
        return total;
    }

    readonly property var queryTokens: {
        const q = root.query.trim().toLowerCase();
        return q.length === 0 ? [] : q.split(/\s+/);
    }

    readonly property var filteredItems: {
        // File mode is its own world: fd already did the filtering, so we
        // just pass its results through. No scoring, no nav-row stitching.
        if (root.fileMode) return root.fileItems;

        const tokens = root.queryTokens;
        const filter = root.categoryFilter;
        const cap = root.maxResults;

        // Pool selection:
        //   drilled (filter set) -> only items matching the target category
        //   root                 -> navigators on top, then everything
        const pool = filter !== ""
            ? root.allItems.filter(it => it.category === filter)
            : root.nav.concat(root.allItems);

        // Empty query: preserve insertion order (nav rows first, then
        // omarchy actions, then apps). No scoring, no allocation overhead.
        if (tokens.length === 0) {
            return pool.length <= cap ? pool : pool.slice(0, cap);
        }

        const scored = [];
        for (let i = 0; i < pool.length; i++) {
            const it = pool[i];
            const s = root.scoreItem(it, tokens);
            if (s > 0) scored.push({ s: s, item: it });
        }
        scored.sort((a, b) => {
            if (b.s !== a.s) return b.s - a.s;
            // Tie-break: nav rows come first so a typed "setup" surfaces
            // the Setup drill-in row above any Setup-category leaf.
            const aCat = a.item.isCategory ? 0 : 1;
            const bCat = b.item.isCategory ? 0 : 1;
            if (aCat !== bCat) return aCat - bCat;
            return a.item.title.localeCompare(b.item.title);
        });
        const lim = Math.min(scored.length, cap);
        const out = new Array(lim);
        for (let j = 0; j < lim; j++) out[j] = scored[j].item;
        return out;
    }

    onFilteredItemsChanged: {
        root.selectedIndex = Math.max(0, Math.min(root.selectedIndex,
                                                  root.filteredItems.length - 1));
    }

    // ---------- Selection movement ----------
    // Single entry point for keyboard nav so arrow/Tab/Page bindings stay
    // one-liners. `wrap` toggles modulo behaviour vs. clamp — arrow + Tab
    // wrap, paging clamps (matches list-widget convention everywhere else).
    function moveSelection(delta, wrap) {
        const n = root.filteredItems.length;
        if (n === 0) return;
        let next = root.selectedIndex + delta;
        next = wrap ? ((next % n) + n) % n
                    : Math.max(0, Math.min(n - 1, next));
        root.selectedIndex = next;
        resultList.positionViewAtIndex(next, ListView.Contain);
    }

    Component.onCompleted: {
        root.omarchy = root.annotate(root.omarchyItems);
        root.nav     = root.annotate(root.categoryNav);
        root.allItems = root.omarchy.slice();
        appScan.running = true;
    }

    // ---------- IPC ----------
    IpcHandler {
        target: "palette"
        function toggle(): void { root.toggle() }
        function open(): void { root.open() }
        function close(): void { root.close() }
        function refresh(): void { appScan.running = false; appScan.running = true; }
    }

    // ---------- Panel ----------
    PanelWindow {
        id: panel
        visible: root.visible_ || reveal > 0.001
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "omni-menu"
        WlrLayershell.keyboardFocus: root.visible_ ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        property real reveal: root.visible_ ? 1 : 0
        Behavior on reveal {
            NumberAnimation {
                duration: root.visible_ ? 220 : 140
                easing.type: root.visible_ ? Easing.OutCubic : Easing.InCubic
            }
        }

        // Outside-click dismiss.
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Rectangle {
            id: card
            anchors.horizontalCenter: parent.horizontalCenter
            // Card sits slightly above visual centre so the result list grows
            // downward without dragging the search field out of the eyeline.
            y: parent.height * 0.18
            // Wide enough in file mode for a ~520px preview pane next to
            // the ~440px result list; narrow back to 640 at root so apps/
            // omarchy mode keeps its compact feel.
            width: root.fileMode ? 1000 : 640
            Behavior on width {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
            // Cap the card so it never exceeds the screen even on small
            // displays; cardCol implicitHeight covers the search + list +
            // footer block.
            height: Math.min(cardCol.implicitHeight + 34, parent.height * 0.72)
            color: root.bg
            border.color: root.sep
            border.width: 1
            radius: 0
            transformOrigin: Item.Center
            scale: panel.reveal

            // Swallow clicks so the underlying dismiss MouseArea doesn't fire.
            MouseArea { anchors.fill: parent }

            focus: root.visible_
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    // First Esc steps out of a drilled-in category; a
                    // second Esc closes the palette. Drives muscle-memory
                    // closer to "back" than to "close everything".
                    if (!root.goUp()) root.close();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down
                           || (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier))) {
                    // Tab + Down step forward, Shift+Tab + Up step backward,
                    // both wrap. Paging clamps (see Key_PageDown). Matches
                    // launcher convention everywhere else.
                    root.moveSelection(1, true);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up
                           || event.key === Qt.Key_Backtab
                           || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                    root.moveSelection(-1, true);
                    event.accepted = true;
                } else if (event.key === Qt.Key_PageDown) {
                    root.moveSelection(8, false);
                    event.accepted = true;
                } else if (event.key === Qt.Key_PageUp) {
                    root.moveSelection(-8, false);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Home) {
                    root.selectedIndex = 0;
                    resultList.positionViewAtIndex(0, ListView.Beginning);
                    event.accepted = true;
                } else if (event.key === Qt.Key_End) {
                    root.selectedIndex = Math.max(0, root.filteredItems.length - 1);
                    resultList.positionViewAtIndex(root.selectedIndex, ListView.End);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    const it = root.filteredItems[root.selectedIndex];
                    if (it) root.activate(it);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Backspace) {
                    // Backspace deletes a char first; once the query is
                    // empty it walks back up one level so the same key
                    // unwinds both the typed query and the breadcrumb.
                    if (root.query.length > 0) root.query = root.query.slice(0, -1);
                    else root.goUp();
                    event.accepted = true;
                } else if (event.text && event.text.length === 1) {
                    const ch = event.text;
                    // Printable range; lets letters, digits, and spaces in,
                    // keeps modifier-driven control codes out.
                    if (ch.charCodeAt(0) >= 32 && ch.charCodeAt(0) !== 127) {
                        root.query += ch;
                        root.selectedIndex = 0;
                        event.accepted = true;
                    }
                }
            }

            Column {
                id: cardCol
                anchors.fill: parent
                anchors.margins: 17
                spacing: 12

                Item {
                    width: parent.width
                    height: 43

                    Column {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            text: root.categoryFilter === ""
                                  ? "OMNI"
                                  : "OMNI › " + root.sectionIcon + "  " + root.categoryFilter.toUpperCase()
                            color: root.ink
                            font.family: root.mono
                            font.pixelSize: 19
                            font.letterSpacing: 4
                            font.weight: Font.Medium
                        }
                        Text {
                            text: {
                                if (!root.appsLoaded) return "LOADING APPS…";
                                if (root.fileMode) {
                                    if (root.query.length === 0) return "TYPE TO SEARCH ~";
                                    if (root.fdRunning) return "SEARCHING…";
                                    const total = root.filteredItems.length;
                                    return total === 0
                                        ? "NO FILES MATCH"
                                        : total + " FILE" + (total === 1 ? "" : "S");
                                }
                                const total = root.filteredItems.length;
                                if (root.query.length === 0) {
                                    return total + " ENTRIES  ·  " + root.allItems.length + " TOTAL";
                                }
                                return total === 0
                                    ? "NO MATCHES"
                                    : total + " MATCH" + (total === 1 ? "" : "ES");
                            }
                            color: root.sumi
                            font.family: root.mono
                            font.pixelSize: 11
                            font.letterSpacing: 2
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.categoryFilter === ""
                              ? "↑↓ / TAB  ·  ↵ OPEN  ·  ESC CLOSE"
                              : "↑↓ / TAB  ·  ↵ " + (root.fileMode ? "OPEN FILE" : "RUN") + "  ·  ESC BACK"
                        color: root.sumi
                        font.family: root.mono
                        font.pixelSize: 10
                        font.letterSpacing: 2
                        opacity: 0.6
                    }
                }

                Rectangle { width: parent.width; height: 1; color: root.sep }

                // No focus indicator on TextInput — the caret and the
                // live count above act as the focus tell.
                Item {
                    width: parent.width
                    height: 34

                    Text {
                        id: searchPrompt
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        // Folder-search in file mode; magnifier elsewhere.
                        text: root.fileMode ? "󰉖" : "󰍉"
                        color: root.seal
                        font.family: root.mono
                        font.pixelSize: 16
                    }

                    Text {
                        id: queryText
                        anchors.left: searchPrompt.right
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.query.length === 0
                              ? (root.fileMode
                                 ? "Type to search files in ~ …"
                                 : "Type to search apps, themes, settings…")
                              : root.query
                        color: root.query.length === 0 ? root.sumi : root.ink
                        opacity: root.query.length === 0 ? 0.5 : 1.0
                        font.family: root.mono
                        font.pixelSize: 14
                        font.letterSpacing: 1
                    }

                    // Blinking caret riding the end of the query.
                    Rectangle {
                        id: caret
                        width: 2
                        height: 16
                        color: root.seal
                        anchors.verticalCenter: parent.verticalCenter
                        x: root.query.length === 0
                           ? searchPrompt.x + searchPrompt.width + 10
                           : queryText.x + queryText.contentWidth + 2
                        visible: root.visible_
                        SequentialAnimation on opacity {
                            running: root.visible_
                            loops: Animation.Infinite
                            NumberAnimation { from: 1; to: 0.2; duration: 600; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 0.2; to: 1; duration: 600; easing.type: Easing.InOutSine }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: root.sep }

                // Fixed row height in the delegate keeps positionViewAtIndex
                // honest under fast keyboard navigation; the wrapping Item's
                // clip prevents the bottom row bleeding into the footer
                // hairline mid-scroll.
                Item {
                    id: listArea
                    width: parent.width
                    height: Math.max(60, card.height - 34 - 43 - 34 - 22 - 12 * 5)
                    clip: true

                    // In file mode the list shrinks to ~44% of the card so
                    // a 520px-ish preview pane fits alongside it. The 1px
                    // hairline + 1px inverse hairline divider sits between
                    // them. animated alongside card.width for a single
                    // smooth widen-and-split motion.
                    readonly property real listFraction: root.fileMode ? 0.44 : 1.0

                    ListView {
                        id: resultList
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        // Follows card.width's Behavior animation — adding a
                        // second Behavior here would animate to a moving
                        // target and produce staggered motion.
                        width: parent.width * listArea.listFraction
                        model: root.filteredItems
                        currentIndex: root.selectedIndex
                        highlightFollowsCurrentItem: false
                        boundsBehavior: Flickable.StopAtBounds
                        cacheBuffer: 200
                        // Snap pixel-perfect so the row outline doesn't
                        // shimmer during arrow-key scroll.
                        pixelAligned: true

                        delegate: Item {
                            id: row
                            required property var modelData
                            required property int index
                            width: ListView.view.width
                            height: 38
                            readonly property bool isSelected: root.selectedIndex === index

                            Rectangle {
                                anchors.fill: parent
                                color: row.isSelected ? root.rowSel
                                                       : rowMouse.containsMouse ? root.rowHi
                                                                                : "transparent"
                                Behavior on color { ColorAnimation { duration: 90 } }
                            }
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 2
                                color: root.seal
                                visible: row.isSelected
                            }

                            // Icon slot: tinted .desktop image when one
                            // resolves, nerd-font glyph fallback otherwise.
                            // hasImageIcon flips on Image.Ready so the swap
                            // happens in one frame, no broken-icon flash.
                            Item {
                                id: iconText
                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22
                                height: 22

                                readonly property string iconUrl: root.resolveIconUrl(row.modelData.rawIcon)
                                readonly property bool hasImageIcon: appImg.status === Image.Ready && iconUrl !== ""
                                readonly property color tint: row.isSelected ? root.seal : root.inkDeep

                                Text {
                                    anchors.centerIn: parent
                                    visible: !iconText.hasImageIcon
                                    text: row.modelData.icon || "·"
                                    color: iconText.tint
                                    font.family: root.mono
                                    font.pixelSize: 16
                                }

                                // Hidden because MultiEffect draws the
                                // recoloured copy; layer.enabled hands it
                                // a texture to sample without committing a
                                // full FBO until an icon actually resolves.
                                Image {
                                    id: appImg
                                    anchors.centerIn: parent
                                    width: 18
                                    height: 18
                                    visible: false
                                    source: iconText.iconUrl
                                    sourceSize.width: 36
                                    sourceSize.height: 36
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    asynchronous: true
                                    cache: true
                                    layer.enabled: iconText.hasImageIcon
                                }
                                // colorization: 1.0 paints solid colour
                                // through the source's alpha — a flat
                                // tinted silhouette in the ink/seal palette.
                                MultiEffect {
                                    anchors.fill: appImg
                                    visible: iconText.hasImageIcon
                                    source: appImg
                                    colorization: 1.0
                                    colorizationColor: iconText.tint
                                    Behavior on colorizationColor { ColorAnimation { duration: 90 } }
                                }
                            }
                            Text {
                                id: titleText
                                anchors.left: iconText.right
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                // Trailing chevron flags drill-in rows so
                                // you can tell at a glance which Enters
                                // drill in vs. which Enters execute.
                                text: row.modelData.isCategory
                                      ? row.modelData.title + "  ›"
                                      : row.modelData.title
                                color: row.isSelected ? root.ink : root.fg
                                font.family: root.mono
                                font.pixelSize: 13
                                font.weight: row.isSelected ? Font.Medium : Font.Light
                                font.letterSpacing: 1
                                elide: Text.ElideRight
                                width: row.width - iconText.width - catText.implicitWidth - 60
                            }
                            Text {
                                id: catText
                                anchors.right: parent.right
                                anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                // File rows show the dirname here, which
                                // shouldn't be uppercased or letter-spaced.
                                // Cap the width so a deep path doesn't push
                                // the title text off the row.
                                text: row.modelData.isFile
                                      ? (row.modelData.category || "")
                                      : (row.modelData.category || "").toUpperCase()
                                color: row.isSelected ? root.seal : root.sumi
                                opacity: row.isSelected ? 0.95 : 0.65
                                font.family: root.mono
                                font.pixelSize: 10
                                font.letterSpacing: row.modelData.isFile ? 0 : 2
                                elide: Text.ElideLeft
                                horizontalAlignment: Text.AlignRight
                                width: row.modelData.isFile
                                       ? Math.min(implicitWidth, row.width * 0.45)
                                       : implicitWidth
                            }

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                // onPositionChanged fires only on actual
                                // cursor movement; onEntered would also
                                // fire when rows shift under a stationary
                                // cursor (after a query change, drill-in,
                                // or rescore), stealing keyboard focus.
                                onPositionChanged: root.selectedIndex = row.index
                                onClicked: root.activate(row.modelData)
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: resultList.count === 0
                            text: {
                                if (root.fileMode) {
                                    if (root.query.length === 0) return "TYPE TO SEARCH ~";
                                    if (root.fdRunning) return "SEARCHING…";
                                    return "NO FILES MATCH";
                                }
                                return root.appsLoaded ? "NOTHING MATCHES" : "INDEXING APPS…";
                            }
                            color: root.sumi
                            font.family: root.mono
                            font.pixelSize: 11
                            font.letterSpacing: 3
                            opacity: 0.6
                        }
                    }

                    // ---------- Preview pane ----------
                    // Vertical hairline separating the list from the
                    // preview. Hidden at root, fades in via the
                    // listFraction-driven layout when file mode flips on.
                    Rectangle {
                        visible: root.fileMode
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: resultList.right
                        width: 1
                        color: root.sep
                    }

                    Item {
                        id: previewPane
                        visible: root.fileMode
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: resultList.right
                        anchors.leftMargin: 13
                        anchors.right: parent.right

                        // Wraps so a long filename doesn't elide into
                        // uselessness; capped at 2 lines for body room.
                        Text {
                            id: previewName
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            text: root.previewPath ? root.basename(root.previewPath) : ""
                            color: root.ink
                            font.family: root.mono
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            font.letterSpacing: 1
                            wrapMode: Text.WrapAnywhere
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                        Text {
                            id: previewDir
                            anchors.top: previewName.bottom
                            anchors.topMargin: 2
                            anchors.left: parent.left
                            anchors.right: parent.right
                            text: root.previewPath
                                  ? root.tildify(root.dirname(root.previewPath))
                                  : ""
                            color: root.sumi
                            font.family: root.mono
                            font.pixelSize: 10
                            font.letterSpacing: 1
                            elide: Text.ElideLeft
                            opacity: 0.75
                        }
                        Rectangle {
                            id: previewSep
                            anchors.top: previewDir.bottom
                            anchors.topMargin: 8
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 1
                            color: root.sep
                            visible: root.previewPath !== ""
                        }

                        Item {
                            id: previewBody
                            anchors.top: previewSep.bottom
                            anchors.topMargin: 10
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            clip: true

                            Text {
                                anchors.centerIn: parent
                                visible: root.previewPath === ""
                                text: root.query.length === 0
                                      ? "PREVIEW APPEARS HERE"
                                      : "SELECT A FILE"
                                color: root.sumi
                                font.family: root.mono
                                font.pixelSize: 10
                                font.letterSpacing: 3
                                opacity: 0.5
                            }

                            // sourceSize caps decode memory so a 6000x4000
                            // photo doesn't allocate its full pixel buffer
                            // just to render at ~500px.
                            Image {
                                anchors.fill: parent
                                anchors.margins: 4
                                visible: root.previewKind === "image"
                                source: root.previewKind === "image"
                                        ? "file://" + root.previewPath
                                        : ""
                                sourceSize.width: 1024
                                sourceSize.height: 1024
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                smooth: true
                            }

                            Text {
                                anchors.fill: parent
                                visible: root.previewKind === "text"
                                text: root.previewText
                                color: root.ink
                                font.family: root.mono
                                font.pixelSize: 10
                                lineHeight: 1.3
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                maximumLineCount: Math.max(1, Math.floor(previewBody.height / 13))
                            }

                            Text {
                                anchors.fill: parent
                                visible: root.previewKind === "meta"
                                text: root.previewMeta
                                color: root.sumi
                                font.family: root.mono
                                font.pixelSize: 11
                                lineHeight: 1.4
                                wrapMode: Text.WordWrap
                                textFormat: Text.PlainText
                            }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: root.sep }

                // Footer surfaces the exec line of the current selection so
                // you can verify what's about to fire before pressing Enter.
                Item {
                    width: parent.width
                    height: 22

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 4
                        elide: Text.ElideRight
                        text: {
                            const it = root.filteredItems[root.selectedIndex];
                            if (!it) return "";
                            if (it.isCategory) return "→ open " + it.target.toLowerCase();
                            return "$ " + it.exec;
                        }
                        color: root.sumi
                        font.family: root.mono
                        font.pixelSize: 10
                        font.letterSpacing: 1
                        opacity: 0.65
                    }
                }
            }
        }
    }
}
