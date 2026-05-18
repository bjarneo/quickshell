import QtQuick
import Quickshell.Io
import "Data.js" as Data

// One-shot scan of XDG application directories. configparser handles the
// gnarly bits — section headers, continuation lines, encodings, comments,
// mixed quoting. Result is cached on `apps` (annotated) for the session
// and re-runs only on demand via refresh().
Item {
    id: appScan

    property var apps: []
    property bool loaded: false

    signal scanned()

    function refresh() {
        proc.running = false;
        proc.running = true;
    }

    Process {
        id: proc
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
                appScan.apps = Data.annotate(apps);
                appScan.loaded = true;
                appScan.scanned();
            }
        }
    }

    Component.onCompleted: appScan.refresh()
}
