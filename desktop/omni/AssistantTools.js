.pragma library

// Explicit Omarchy assistant intent catalog. The model never turns these
// into shell; QML maps each tool key to a fixed command allowlist.
var intents = [
    { all: ["downloads", "organize"], tool: "downloads", action: "downloads-organizer" },
    { all: ["downloads", "organise"], tool: "downloads", action: "downloads-organizer" },
    { all: ["downloads", "sort"], tool: "downloads", action: "downloads-organizer" },
    { all: ["downloads", "clean"], tool: "downloads", action: "downloads-organizer" },
    { all: ["downloads", "tidy"], tool: "downloads", action: "downloads-organizer" },
    { all: ["downloads", "declutter"], tool: "downloads", action: "downloads-organizer" },
    { all: ["downloads", "cleanup"], tool: "downloads", action: "downloads-organizer" },
    { all: ["duplicate", "bars"], tool: "quickshell-processes" },
    { all: ["duplicate", "bar"], tool: "quickshell-processes" },
    { all: ["package", "updates"], tool: "updates" },
    { all: ["check", "updates"], tool: "updates" },

    { all: ["downloads", "what"], tool: "downloads" },
    { all: ["downloads", "list"], tool: "downloads" },
    { all: ["downloads", "show"], tool: "downloads" },
    { all: ["downloads", "files"], tool: "downloads" },
    { all: ["downloads", "inside"], tool: "downloads" },
    { all: ["downloads", "folder"], tool: "downloads" },
    { all: ["downloads", "dir"], tool: "downloads" },
    { all: ["downloads", "directory"], tool: "downloads" },
    { all: ["download folder", "what"], tool: "downloads" },
    { all: ["download directory", "show"], tool: "downloads" },
    { all: ["downloads", "organize"], tool: "downloads", action: "downloads-organizer" },
    { all: ["downloads", "organise"], tool: "downloads", action: "downloads-organizer" },
    { all: ["downloads", "sort"], tool: "downloads", action: "downloads-organizer" },
    { all: ["downloads", "clean"], tool: "downloads", action: "downloads-organizer" },
    { all: ["downloads", "tidy"], tool: "downloads", action: "downloads-organizer" },
    { all: ["downloads", "declutter"], tool: "downloads", action: "downloads-organizer" },
    { all: ["downloads", "mess"], tool: "downloads", action: "downloads-organizer" },
    { all: ["downloads", "cleanup"], tool: "downloads", action: "downloads-organizer" },
    { all: ["downloads", "dedupe"], tool: "downloads", action: "downloads-organizer" },
    { all: ["downloads", "partial"], tool: "downloads" },

    { all: ["omarchy", "commands"], tool: "omarchy-commands" },
    { all: ["omarchy", "help"], tool: "omarchy-commands" },
    { all: ["omarchy", "what can"], tool: "omarchy-commands" },
    { all: ["omarchy", "menu"], tool: "omarchy-commands" },
    { all: ["omarchy", "actions"], tool: "omarchy-commands" },
    { all: ["omarchy", "shortcuts"], tool: "omarchy-commands" },
    { all: ["omarchy", "launch"], tool: "omarchy-commands" },
    { all: ["omarchy", "install"], tool: "omarchy-commands" },
    { all: ["omarchy", "update"], tool: "omarchy-commands" },
    { all: ["omarchy", "restart"], tool: "omarchy-commands" },
    { all: ["omarchy", "toggle"], tool: "omarchy-commands" },
    { all: ["omarchy", "capture"], tool: "omarchy-commands" },
    { all: ["omarchy", "reminder"], tool: "omarchy-commands" },
    { all: ["omarchy", "pkg"], tool: "omarchy-commands" },
    { all: ["omarchy", "setup"], tool: "omarchy-commands" },
    { all: ["omarchy", "version"], tool: "omarchy-commands" },

    { all: ["omni", "status"], tool: "quickshell-ipc" },
    { all: ["omni", "running"], tool: "quickshell-ipc" },
    { all: ["omni", "alive"], tool: "quickshell-ipc" },
    { all: ["omni", "ipc"], tool: "quickshell-ipc" },
    { all: ["omni", "palette"], tool: "quickshell-ipc" },
    { all: ["quickshell", "status"], tool: "quickshell-ipc" },
    { all: ["quickshell", "ipc"], tool: "quickshell-ipc" },
    { all: ["quickshell", "running"], tool: "quickshell-processes" },
    { all: ["qs", "desktop"], tool: "quickshell-processes" },
    { all: ["bar", "duplicate"], tool: "quickshell-processes" },
    { all: ["bar", "running"], tool: "quickshell-processes" },
    { all: ["desktop bar", "status"], tool: "quickshell-processes" },
    { all: ["waybar", "status"], tool: "waybar-status" },
    { all: ["waybar", "running"], tool: "waybar-status" },

    { all: ["hyprland", "active window"], tool: "active-window" },
    { all: ["active window"], tool: "active-window" },
    { all: ["focused window"], tool: "active-window" },
    { all: ["current window"], tool: "active-window" },
    { all: ["focused app"], tool: "active-window" },
    { all: ["active app"], tool: "active-window" },
    { all: ["hyprland", "workspaces"], tool: "hypr-workspaces" },
    { all: ["workspace", "list"], tool: "hypr-workspaces" },
    { all: ["workspaces", "show"], tool: "hypr-workspaces" },
    { all: ["hyprland", "monitors"], tool: "hypr-monitors" },
    { all: ["monitor", "layout"], tool: "hypr-monitors" },
    { all: ["display", "layout"], tool: "hypr-monitors" },
    { all: ["hyprland", "clients"], tool: "hypr-clients" },
    { all: ["windows", "list"], tool: "hypr-clients" },
    { all: ["open windows"], tool: "hypr-clients" },
    { all: ["hyprland", "errors"], tool: "hypr-errors" },
    { all: ["hyprland", "config errors"], tool: "hypr-errors" },

    { all: ["theme", "current"], tool: "omarchy-theme" },
    { all: ["current theme"], tool: "omarchy-theme" },
    { all: ["omarchy", "theme"], tool: "omarchy-theme" },
    { all: ["themes", "list"], tool: "omarchy-theme" },
    { all: ["theme", "colors"], tool: "omarchy-theme" },
    { all: ["aether", "status"], tool: "aether" },
    { all: ["aether", "blueprints"], tool: "aether" },
    { all: ["blueprints", "list"], tool: "aether" },
    { all: ["wallpaper", "current"], tool: "omarchy-theme" },
    { all: ["appearance", "current"], tool: "omarchy-theme" },

    { all: ["screenshots", "recent"], tool: "screenshots" },
    { all: ["screenshots", "show"], tool: "screenshots" },
    { all: ["screenshot", "where"], tool: "screenshots" },
    { all: ["pictures", "screenshots"], tool: "screenshots" },
    { all: ["recordings", "recent"], tool: "recordings" },
    { all: ["videos", "recent"], tool: "recordings" },
    { all: ["screen recordings"], tool: "recordings" },
    { all: ["recording", "where"], tool: "recordings" },

    { all: ["system", "status"], tool: "system-overview" },
    { all: ["machine", "status"], tool: "system-overview" },
    { all: ["computer", "status"], tool: "system-overview" },
    { all: ["pc", "status"], tool: "system-overview" },
    { all: ["resources", "usage"], tool: "system-overview" },
    { all: ["uptime"], tool: "system-overview" },
    { all: ["load average"], tool: "system-overview" },
    { all: ["memory", "usage"], tool: "system-overview" },
    { all: ["ram", "usage"], tool: "system-overview" },
    { all: ["cpu", "usage"], tool: "processes" },
    { all: ["what time"], tool: "date" },
    { all: ["current time"], tool: "date" },
    { all: ["date today"], tool: "date" },

    { all: ["disk", "space"], tool: "storage" },
    { all: ["storage", "left"], tool: "storage" },
    { all: ["storage", "usage"], tool: "storage" },
    { all: ["home", "space"], tool: "storage" },
    { all: ["filesystem", "usage"], tool: "storage" },
    { all: ["drive", "space"], tool: "storage" },
    { all: ["downloads", "size"], tool: "storage" },
    { all: ["big files"], tool: "large-files" },
    { all: ["large files"], tool: "large-files" },
    { all: ["what is taking space"], tool: "large-files" },

    { all: ["processes", "running"], tool: "processes" },
    { all: ["top processes"], tool: "processes" },
    { all: ["cpu", "heavy"], tool: "processes" },
    { all: ["memory", "heavy"], tool: "processes" },
    { all: ["ram", "heavy"], tool: "processes" },
    { all: ["apps", "running"], tool: "processes" },
    { all: ["programs", "running"], tool: "processes" },
    { all: ["tasks", "running"], tool: "processes" },
    { all: ["services", "failed"], tool: "user-services" },
    { all: ["services", "running"], tool: "user-services" },
    { all: ["systemd", "user"], tool: "user-services" },
    { all: ["units", "failed"], tool: "user-services" },
    { all: ["logs", "errors"], tool: "logs" },
    { all: ["journal", "errors"], tool: "logs" },
    { all: ["recent errors"], tool: "logs" },
    { all: ["troubleshoot", "errors"], tool: "troubleshoot" },

    { all: ["network", "status"], tool: "network" },
    { all: ["internet", "status"], tool: "network" },
    { all: ["wifi", "status"], tool: "network" },
    { all: ["wi fi", "status"], tool: "network" },
    { all: ["connection", "status"], tool: "network" },
    { all: ["ip address"], tool: "network" },
    { all: ["local ip"], tool: "network" },
    { all: ["routes"], tool: "network" },
    { all: ["dns", "status"], tool: "network" },

    { all: ["packages", "installed"], tool: "packages" },
    { all: ["installed packages"], tool: "packages" },
    { all: ["explicit packages"], tool: "packages" },
    { all: ["pacman", "packages"], tool: "packages" },
    { all: ["aur", "packages"], tool: "packages" },
    { all: ["package count"], tool: "packages" },
    { all: ["updates", "available"], tool: "updates" },
    { all: ["check updates"], tool: "updates" },
    { all: ["pacman", "updates"], tool: "updates" },

    { all: ["recent files"], tool: "recent-files" },
    { all: ["files", "recent"], tool: "recent-files" },
    { all: ["changed files"], tool: "recent-files" },
    { all: ["modified files"], tool: "recent-files" },
    { all: ["home", "recent"], tool: "recent-files" },
    { all: ["desktop", "files"], tool: "desktop-files" },
    { all: ["documents", "recent"], tool: "documents" },
    { all: ["docs", "recent"], tool: "documents" },
    { all: ["trash", "status"], tool: "trash" },
    { all: ["environment", "session"], tool: "session" },
    { all: ["session", "type"], tool: "session" },
    { all: ["wayland", "session"], tool: "session" }
];

function normalize(text) {
    return (text || "")
        .toLowerCase()
        .replace(/[’]/g, "'")
        .replace(/[-_/]+/g, " ")
        .replace(/[^a-z0-9'$ .]+/g, " ")
        .replace(/\s+/g, " ")
        .trim();
}

function itemMatches(prompt, item) {
    if (item.phrase && prompt.indexOf(normalize(item.phrase)) !== -1)
        return true;
    if (item.all) {
        for (var i = 0; i < item.all.length; i++) {
            if (prompt.indexOf(normalize(item.all[i])) === -1)
                return false;
        }
        return true;
    }
    return false;
}

function findIntent(text) {
    var prompt = normalize(text);
    if (prompt.length === 0)
        return null;
    for (var i = 0; i < intents.length; i++) {
        if (itemMatches(prompt, intents[i]))
            return intents[i];
    }
    return null;
}
