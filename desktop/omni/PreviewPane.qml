import QtQuick
import "../Data.js" as Data
import "Format.js" as Fmt

// Right-side preview pane. Shown when one of the preview-bearing modes
// (file, gh, proc, theme, tldr, chat) is active. Surfaces a header
// (name + path/status), a hairline, and then a mode-specific body:
// image / text / meta / tldr-RichText / chat-RichText / readme /
// process detail / theme swatches.
//
// The flickable + text edits are aliased so the OmniMenu key handler
// can drive scrolling, selection, and clipboard copy from outside.
Item {
    id: pp

    required property var omni
    required property var ollamaChat

    property alias tldrFlickable: tldrPreviewScroll
    property alias chatFlickable: chatPreviewScroll
    property alias tldrEdit:      tldrPreviewEdit
    property alias chatEdit:      chatPreviewEdit
    property alias chatPlain:     chatPlainShadow

    Text {
        id: previewName
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        text: {
            const o = pp.omni;
            const it = o.filteredItems[o.selectedIndex];
            if (o.tldrMode) return o.tldrTool;
            if (o.chatMode) return o.chatModel;
            if (o.ghMode) return o.previewRepo;
            if (o.procMode) return it ? it.title : "";
            if (o.themeMode) return it ? it.title : "";
            return o.previewPath ? Data.basename(o.previewPath) : "";
        }
        color: pp.omni.ink
        font.family: pp.omni.mono
        font.pixelSize: 13 * pp.omni.fontScale
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
        text: {
            const o = pp.omni;
            const it = o.filteredItems[o.selectedIndex];
            if (o.tldrMode) return o.tldrTool.length === 0
                ? "type a command name after $"
                : "tldr  ·  ↵ opens terminal with command ready";
            if (o.chatMode) {
                if (o.chatPrompt.length === 0) return "type a question after ?";
                if (o.chatStatus === "")    return "probing local ollama…";
                if (o.chatStatus === "no-ollama") return "install ollama first";
                if (o.chatStatus === "no-daemon") return "↵ to start the ollama daemon";
                if (o.chatStatus === "no-model")  return "↵ to pull " + o.chatModel + " (~1 GB)";
                if (!o.chatSubmitted)        return "↵ to ask  ·  local, offline";
                if (o.chatRunning)           return "working  ·  edit to ask again";
                if (o.chatActionCommand !== "") return "↵ runs fixed action  ·  action ready";
                return "↵ done  ·  edit prompt and ↵ to ask again";
            }
            if (o.ghMode) return o.previewRepoUrl;
            if (o.procMode) return it ? ("pid " + (it.pid || "") + "  ·  ↵ kills (SIGTERM)") : "";
            if (o.themeMode) return it
                ? (it.isActive ? "ACTIVE  ·  ↵ reapplies" : "↵ applies theme")
                : "";
            return o.previewPath ? Data.tildify(Data.dirname(o.previewPath), o.homeDir) : "";
        }
        color: pp.omni.inkDeep
        font.family: pp.omni.mono
        font.pixelSize: 10 * pp.omni.fontScale
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
        color: pp.omni.sep
        visible: pp.omni.previewHasContent
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
            visible: !pp.omni.previewHasContent
            text: {
                const o = pp.omni;
                if (o.tldrMode) {
                    if (o.tldrTool.length === 0) return "TYPE A COMMAND";
                    return o.tldrRunning ? "FETCHING…" : "NO TLDR PAGE";
                }
                if (o.chatMode) {
                    if (o.chatPrompt.length === 0) return "TYPE A QUESTION";
                    if (o.chatStatus === "") return "CHECKING…";
                    if (!o.chatSubmitted) return "PRESS ENTER TO ASK";
                    return o.chatRunning ? "WORKING…" : "DONE";
                }
                if (o.ghMode)    return "SELECT A REPO";
                if (o.procMode)  return "SELECT A PROCESS";
                if (o.themeMode) return "SELECT A THEME";
                return o.query.length === 0 ? "PREVIEW APPEARS HERE" : "SELECT A FILE";
            }
            color: pp.omni.inkDeep
            font.family: pp.omni.mono
            font.pixelSize: 10 * pp.omni.fontScale
            font.letterSpacing: 3
            opacity: 0.5
        }

        // sourceSize caps decode memory so a 6000x4000 photo doesn't
        // allocate its full pixel buffer just to render at ~500px.
        Image {
            anchors.fill: parent
            anchors.margins: 4
            visible: pp.omni.previewKind === "image"
            source: pp.omni.previewKind === "image"
                    ? "file://" + pp.omni.previewPath
                    : ""
            sourceSize.width: 1024
            sourceSize.height: 1024
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
        }

        Text {
            anchors.fill: parent
            visible: pp.omni.previewKind === "text"
            text: pp.omni.previewText
            color: pp.omni.ink
            font.family: pp.omni.mono
            font.pixelSize: 10 * pp.omni.fontScale
            lineHeight: 1.3
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            elide: Text.ElideRight
            maximumLineCount: Math.max(1, Math.floor(previewBody.height / 13))
        }

        Text {
            anchors.fill: parent
            visible: pp.omni.previewKind === "meta"
            text: pp.omni.previewMeta
            color: pp.omni.inkDeep
            font.family: pp.omni.mono
            font.pixelSize: 11 * pp.omni.fontScale
            lineHeight: 1.4
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
        }

        // Wheel-scrollable preview. `interactive: false` disables
        // Flickable's own drag-to-scroll so the inner TextEdit's
        // drag-to-select wins; wheel events still scroll via
        // Flickable's separate wheel handling. contentY resets to 0
        // whenever the tldr text changes so a fresh fetch always
        // starts at the top.
        Flickable {
            id: tldrPreviewScroll
            anchors.fill: parent
            visible: pp.omni.tldrMode && pp.omni.tldrPreview !== ""
            contentWidth: width
            contentHeight: tldrPreviewEdit.implicitHeight
            clip: true
            interactive: false
            boundsBehavior: Flickable.StopAtBounds

            Connections {
                target: pp.omni
                function onTldrPreviewChanged() { tldrPreviewScroll.contentY = 0; }
            }

            // Mouse wheel scroll. Flickable's built-in wheel handling
            // is gated by `interactive`, which we keep false so
            // TextEdit can own drag-to-select. A WheelHandler bypasses
            // that gate, scrolling contentY directly.
            WheelHandler {
                onWheel: (event) => {
                    const f = tldrPreviewScroll;
                    const max = Math.max(0, f.contentHeight - f.height);
                    f.contentY = Math.max(0, Math.min(max,
                        f.contentY - event.angleDelta.y * 0.5));
                }
            }

            // TextEdit (not Text) so the user can mouse-drag to select
            // and copy. activeFocusOnPress false means clicking in the
            // preview doesn't steal keystrokes from the search input;
            // selection still tracks the mouse and Ctrl+C at the root
            // key handler copies via the edit's copy() method.
            // persistentSelection keeps the highlight visible while
            // focus stays on the search input.
            TextEdit {
                id: tldrPreviewEdit
                width: tldrPreviewScroll.width
                text: Fmt.formatTldrHtml(pp.omni.tldrPreview, {
                    ink: pp.omni.ink, inkDeep: pp.omni.inkDeep,
                    indigo: pp.omni.indigo, seal: pp.omni.seal
                })
                color: pp.omni.ink
                font.family: pp.omni.mono
                font.pixelSize: 13 * pp.omni.fontScale
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.RichText
                readOnly: true
                selectByMouse: true
                persistentSelection: true
                activeFocusOnPress: false
                selectionColor: pp.omni.indigo
                selectedTextColor: pp.omni.paper
            }
        }

        // Chat preview - same scroll/select/copy shape as the tldr
        // one above. Shows the setup hint text when status is not
        // "ok", otherwise shows the streamed response. Auto-scrolls
        // to the bottom while running so the user sees the latest
        // tokens.
        Flickable {
            id: chatPreviewScroll
            anchors.fill: parent
            visible: pp.omni.chatMode && pp.omni.previewHasContent
            contentWidth: width
            contentHeight: chatPreviewEdit.implicitHeight
            clip: true
            interactive: false
            boundsBehavior: Flickable.StopAtBounds

            Connections {
                target: pp.omni
                function onChatPreviewChanged() {
                    if (pp.omni.chatRunning) {
                        const max = Math.max(0, chatPreviewScroll.contentHeight - chatPreviewScroll.height);
                        chatPreviewScroll.contentY = max;
                    }
                }
            }
            // Reset scroll only on *new submissions* - listening to
            // the signal (not the submitted property) avoids
            // resetting when prompt-edit flips submitted false,
            // which would slam contentY=0 mid-read.
            Connections {
                target: pp.ollamaChat
                function onPromptSubmitted() {
                    chatPreviewScroll.contentY = 0;
                }
            }

            WheelHandler {
                onWheel: (event) => {
                    const f = chatPreviewScroll;
                    const max = Math.max(0, f.contentHeight - f.height);
                    f.contentY = Math.max(0, Math.min(max,
                        f.contentY - event.angleDelta.y * 0.5));
                }
            }

            // Hidden plain-text mirror of chatPreview. Used by Ctrl+C
            // (no-selection path) to put the raw markdown on the
            // clipboard with backticks and bullet hyphens preserved -
            // Qt's RichText→plain conversion strips those when
            // copy()ing from chatPreviewEdit.
            TextEdit {
                id: chatPlainShadow
                visible: false
                width: 0
                height: 0
                text: pp.omni.chatPreview
                textFormat: TextEdit.PlainText
                readOnly: true
            }
            TextEdit {
                id: chatPreviewEdit
                width: chatPreviewScroll.width
                // Status messages get dimmed via the baseColor arg;
                // live response uses the default ink. formatChatHtml
                // escapes HTML and converts newlines to <br> so plain
                // status text is safe under RichText too.
                text: {
                    const o = pp.omni;
                    const pal = { ink: o.ink, inkDeep: o.inkDeep,
                                  indigo: o.indigo, seal: o.seal };
                    if (o.chatStatus === "no-ollama")
                        return Fmt.formatChatHtml(
                            "Ollama is not installed.\n\n"
                          + "Install it from your package manager:\n"
                          + "  `yay -S ollama`\n"
                          + "  `sudo systemctl enable --now ollama`\n"
                          + "  `ollama pull " + o.chatModel + "`\n\n"
                          + "Then return here and try again.", pal, o.inkDeep);
                    if (o.chatStatus === "no-daemon")
                        return Fmt.formatChatHtml(
                            "Ollama is installed but the daemon is not responding.\n\n"
                          + "Press Enter to start it in a terminal. "
                          + "You can close the terminal once you see the daemon is up.", pal, o.inkDeep);
                    if (o.chatStatus === "no-model")
                        return Fmt.formatChatHtml(
                            "Model `" + o.chatModel + "` is not pulled yet (~1 GB).\n\n"
                          + "Press Enter to fetch it. This is a one-time download; "
                          + "the weights live at `~/.ollama/models/`.", pal, o.inkDeep);
                    return Fmt.formatChatHtml(o.chatPreview, pal, null);
                }
                color: pp.omni.ink
                font.family: pp.omni.mono
                font.pixelSize: 13 * pp.omni.fontScale
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.RichText
                readOnly: true
                selectByMouse: true
                persistentSelection: true
                activeFocusOnPress: false
                selectionColor: pp.omni.indigo
                selectedTextColor: pp.omni.paper
            }
        }

        Text {
            anchors.fill: parent
            visible: pp.omni.ghMode && pp.omni.previewRepoUrl !== ""
            text: pp.omni.previewReadme
            color: pp.omni.ink
            font.family: pp.omni.mono
            font.pixelSize: 10 * pp.omni.fontScale
            lineHeight: 1.3
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            elide: Text.ElideRight
            maximumLineCount: Math.max(1, Math.floor(previewBody.height / 13))
        }

        // Process detail (cmdline + ps stats).
        Text {
            anchors.fill: parent
            visible: pp.omni.procMode && pp.omni.procPreviewText !== ""
            text: pp.omni.procPreviewText
            color: pp.omni.ink
            font.family: pp.omni.mono
            font.pixelSize: 10 * pp.omni.fontScale
            lineHeight: 1.4
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }

        // Theme preview image: themes ship a preview.png (lock screen
        // sample) or, when absent, fall back to the first file in the
        // backgrounds/ subdir. Themes.qml resolves the path; missing
        // themes get "" and the image stays invisible so the swatches
        // below take the whole pane.
        Image {
            id: themeImg
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            visible: pp.omni.themeMode && status === Image.Ready
            height: visible ? Math.min(implicitHeight, previewBody.height * 0.6) : 0
            source: {
                if (!pp.omni.themeMode) return "";
                const it = pp.omni.filteredItems[pp.omni.selectedIndex];
                return (it && it.previewImage) ? "file://" + it.previewImage : "";
            }
            fillMode: Image.PreserveAspectFit
            sourceSize.width: 1024
            sourceSize.height: 1024
            asynchronous: true
            smooth: true
            cache: true
        }

        // Theme swatch grid. Each swatch is a 30x30 tile coloured
        // from the theme's colors.toml; Flow lets them reflow if the
        // preview pane is narrowed. Sits under the preview image
        // when one resolves, otherwise pinned to the top of the pane.
        Flow {
            anchors.top: themeImg.visible ? themeImg.bottom : parent.top
            anchors.topMargin: themeImg.visible ? 10 : 0
            anchors.left: parent.left
            anchors.right: parent.right
            visible: pp.omni.themeMode
            spacing: 6
            Repeater {
                model: {
                    const it = pp.omni.filteredItems[pp.omni.selectedIndex];
                    return (it && it.swatches) ? it.swatches : [];
                }
                delegate: Rectangle {
                    required property string modelData
                    width: 30
                    height: 30
                    radius: 2
                    color: modelData
                    border.width: 1
                    border.color: pp.omni.sep
                }
            }
        }
    }
}
