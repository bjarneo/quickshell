import QtQuick
import Quickshell.Io

// Local-LLM chat backend for the omni-menu, triggered by a `?` query
// prefix. Mirrors TldrSearch's shape: a synthetic single-row item plus
// a streamed preview body. The HTTP API at localhost:11434 streams
// NDJSON token chunks which a SplitParser appends to previewText.
//
// State machine (status property):
//   ""           probe still running (transient)
//   "no-ollama"  binary missing — user must install themselves
//   "no-daemon"  binary OK, daemon not responding — Enter starts it
//   "no-model"   daemon OK, model not pulled — Enter pulls it
//   "ok"         everything in place — Enter submits the prompt
//
// Within "ok", `submitted` flips true on Enter and `running` tracks the
// curl subprocess; once running flips back to false the answer is done.
//
// RAM: clear() invokes unloadIfUsed() to release the resident model
// weights (~1 GB for qwen3.5:0.8b) right after the user leaves
// chat mode. The `_usedThisSession` flag guards against unloading a
// model the user warmed via some other tool before opening the
// palette. The ollama daemon itself stays running - we manage only
// our use of it.
Item {
    id: ollamaChat

    required property string query
    required property bool active

    property var items: []
    property string previewText: ""
    property string prompt: ""
    property string status: ""
    property bool submitted: false
    readonly property bool running: chatProc.running

    property int _gen: 0
    readonly property string model_: "qwen3.5:0.8b"

    // Tracks whether THIS session actually invoked inference (vs. just
    // probed the daemon). Without it, leaving the palette while ollama
    // ps already had the model warm from another tool would unload it
    // and surprise the user. Set in submit(), cleared after the unload
    // fires from clear().
    property bool _usedThisSession: false

    // Emitted from submit() so callers can scroll to top / reset
    // state on each *new* submission specifically — not on every
    // prompt edit (which also flips `submitted` false→true→false).
    signal promptSubmitted()
    // Steers the model toward devrel-style answers: lead with the
    // command, use fenced code blocks, no marketing fluff or preamble.
    // Aggressive and concrete because small models follow specific
    // directives better than abstract ones like "be brief".
    readonly property string systemPrompt:
          "You are a terse Linux and CLI assistant for an Arch / Hyprland user. "
        + "Reply in devrel style: short, scannable, no preamble, no apologies. "
        + "Lead with the answer or the exact command. "
        + "Wrap every shell snippet in a fenced ```code``` block. "
        + "Use plain hyphens (-), never em dashes. "
        + "If you don't know, say so in one line. "
        + "Skip restating the question."

    function clear() {
        ollamaChat.items = [];
        ollamaChat.previewText = "";
        ollamaChat.prompt = "";
        ollamaChat.submitted = false;
        ollamaChat._gen += 1;
        chatProc.running = false;
        probeProc.running = false;
        ollamaChat.status = "";
        ollamaChat.refreshItems();
        // If this session actually loaded the model (vs. just probed),
        // ping ollama with keep_alive:0 so the ~2GB of weights are
        // released right away instead of waiting for the daemon's
        // default 5-minute idle timeout. Gated on _usedThisSession so
        // we never unload a model the user warmed up via some other
        // tool before opening the palette.
        ollamaChat.unloadIfUsed();
    }

    // Posts a no-prompt generate with keep_alive:0, which ollama
    // interprets as "unload this model immediately". Fire-and-forget,
    // short timeout so a wedged daemon can't slow the palette close.
    function unloadIfUsed() {
        if (!ollamaChat._usedThisSession) return;
        ollamaChat._usedThisSession = false;
        const body = JSON.stringify({
            model: ollamaChat.model_,
            keep_alive: 0
        });
        unloadProc.command = ["curl", "-s", "--max-time", "2", "-X", "POST",
            "http://localhost:11434/api/generate",
            "-d", body];
        unloadProc.running = false;
        unloadProc.running = true;
    }

    function parseQuery(q) {
        if (q.charAt(0) !== "?") return null;
        return { prompt: q.substring(1).trim() };
    }

    function refreshItems() {
        if (!ollamaChat.active) { ollamaChat.items = []; return; }
        const empty = ollamaChat.prompt.length === 0;
        ollamaChat.items = [{
            title: "ollama " + ollamaChat.model_,
            comment: empty ? "type a question after ?" : ollamaChat.prompt,
            keywords: "",
            category: "ollama",
            icon: "󱚤",
            rawCategory: true,
            isOllama: true
        }];
    }

    function submit() {
        if (ollamaChat.status !== "ok") return;
        if (ollamaChat.prompt.length === 0) return;
        ollamaChat.submitted = true;
        ollamaChat._usedThisSession = true;
        ollamaChat.previewText = "";
        ollamaChat._gen += 1;
        chatProc.gen = ollamaChat._gen;
        // argv-style — the prompt rides inside JSON.stringify'd body so
        // no shell parsing touches its contents.
        //
        // think:false disables Qwen3-family thinking mode. With it on,
        // tokens stream into a separate `thinking` field while
        // `response` stays empty until the model finishes planning,
        // which looks like a frozen panel for the first few seconds.
        // Our devrel-style system prompt already rules out chain-of-
        // thought output anyway. Ignored by non-thinking models.
        const body = JSON.stringify({
            model: ollamaChat.model_,
            prompt: ollamaChat.prompt,
            system: ollamaChat.systemPrompt,
            stream: true,
            think: false
        });
        chatProc.command = ["curl", "-sN",
            "http://localhost:11434/api/generate",
            "-d", body];
        chatProc.running = false;
        chatProc.running = true;
        ollamaChat.promptSubmitted();
    }

    onActiveChanged: {
        if (ollamaChat.active) {
            // Re-probe on every entry: install / pull / daemon-start
            // performed in a previous activation should be picked up
            // without a menu reload.
            ollamaChat.status = "";
            probeProc.running = false;
            probeProc.running = true;
            ollamaChat.refreshItems();
        } else {
            // User backspaced the leading `?` while the menu stayed
            // open. Cancel any in-flight stream so curl + ollama
            // don't keep spending CPU/tokens on an answer no-one is
            // looking at, and bump _gen so late chunks can't backwrite
            // previewText. Keep prompt/items/submitted for the case
            // where they re-type `?` with the same content — clear()
            // is called from close()/category-pivot, not here.
            ollamaChat._gen += 1;
            chatProc.running = false;
        }
    }

    onQueryChanged: {
        if (!ollamaChat.active) return;
        const parsed = ollamaChat.parseQuery(ollamaChat.query);
        const next = parsed ? parsed.prompt : "";
        if (next !== ollamaChat.prompt) {
            ollamaChat.prompt = next;
            ollamaChat.submitted = false;
            ollamaChat.previewText = "";
            // Editing the prompt invalidates any in-flight stream.
            ollamaChat._gen += 1;
            chatProc.running = false;
            ollamaChat.refreshItems();
        }
    }

    // Readiness probe — runs once per chatMode activation. Cheap
    // (<100ms locally). Output is one of the four status strings.
    Process {
        id: probeProc
        running: false
        // Model name is passed positionally as $1 so shell
        // metacharacters / regex characters in it can never
        // re-interpret the command. grep -F treats the pattern as a
        // fixed string (so `.` and `:` in `qwen3.5:0.8b` aren't
        // regex metachars), and `--` separates the flag block from
        // the pattern. Substring match against /api/tags is still
        // technically loose but the model id is distinctive enough
        // that a JSON false-positive is implausible.
        command: ["sh", "-c",
            "if ! command -v ollama >/dev/null 2>&1; then echo no-ollama; exit; fi; "
            + "if ! curl -s --max-time 1 http://localhost:11434/api/tags >/dev/null 2>&1; then echo no-daemon; exit; fi; "
            + "if ! curl -s http://localhost:11434/api/tags | grep -Fq -- \"$1\"; then echo no-model; exit; fi; "
            + "echo ok",
            "sh", ollamaChat.model_]
        stdout: StdioCollector {
            onStreamFinished: { ollamaChat.status = this.text.trim(); }
        }
    }

    // Fire-and-forget keep_alive:0 unload. No stdout handler because
    // we don't care what ollama says — the goal is just to free the
    // RAM. max-time 2 keeps a stuck daemon from blocking palette
    // close.
    Process {
        id: unloadProc
        running: false
        command: ["true"]
    }

    // Streaming inference via Ollama's HTTP API. SplitParser fires on
    // each NDJSON line; we accumulate `response` fields into
    // previewText. Generation token drops stale chunks from a prior
    // dispatch when the user edits the prompt mid-stream.
    Process {
        id: chatProc
        running: false
        command: ["true"]
        property int gen: 0
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                if (chatProc.gen !== ollamaChat._gen) return;
                if (!data || data.length === 0) return;
                try {
                    const obj = JSON.parse(data);
                    if (typeof obj.response === "string" && obj.response.length > 0) {
                        ollamaChat.previewText += obj.response;
                    }
                } catch (e) {
                    // Non-JSON chunk (rare — curl status messages, empty
                    // lines on stream boundary). Silently skip.
                }
            }
        }
    }

}
