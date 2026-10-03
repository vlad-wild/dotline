import QtQuick
import Quickshell
import Quickshell.Io
import "../" as Dotline
import "../components" as Components
import "../services" as Services

// dotline — the launcher: a search pill and a grid of circles (see
// the mock-up's .launcher/.sbox/.apps). Toggled via Quickshell's IPC from
// niri (see shell.qml's IpcHandler and config.kdl's Mod+D bind) rather
// than being its own spawned program, so it matches the rest of the shell
// visually instead of looking like a bolted-on dmenu.
//
// Modes, switched on the query's prefix (plan's "launcher palette" idea —
// still missing `;` [handled separately already, Mod+V/cliphist] and `:`
// [emoji, needs its own searchable data file, not done yet]):
//   (nothing)  app search — unchanged from before
//   =expr      qalc calculator; Enter copies the result (wl-copy)
//   ?query     web search (DuckDuckGo); Enter opens it in the default browser
//   $cmd       shell command; Enter runs it visibly in kitty
//   /win query windows across every workspace (`niri msg --json windows`,
//              already read by services/Niri.qml); Enter focuses it
//   /f query   files under $HOME (`fd`, already in packages/desktop.txt);
//              Enter opens with the default app (`xdg-open`)
//   /app query search pacman + AUR + Flathub (scripts/app search --json);
//              Enter installs visibly in kitty (scripts/app install).
//              Source shown as a [P]/[A]/[F] prefix rather than a real
//              per-source icon — same reasoning as the wifi/phone bar
//              dots elsewhere: a plain, unambiguous marker beats guessing
//              at icon-theme lookups for three different ecosystems.
//   /query     anything else starting with "/" — a short curated list of
//              already-existing IPC calls/scripts. Deliberately leaves out
//              reboot/poweroff: those already live in SystemMenu.qml behind
//              its two-click confirm, and a bare Enter in a search box is
//              the wrong place for a one-press shutdown.
//
// Icon loading is best-effort: `image://icon/<name>` is a guess at Qt's
// icon-theme image provider existing here, with a plain-letter circle as
// the fallback if it fails to load — a failed Image load is a soft runtime
// condition, so getting this guess wrong costs an icon, not the launcher.
Item {
    id: root

    property bool open: false
    readonly property int columns: 6
    readonly property real cellSize: 104

    function show() {
        root.open = true
        query.text = ""
        selected = 0
        // deferred one tick: the window this sits in only becomes visible
        // (and so, mappable/focusable) from the `open` binding above, which
        // may not have taken effect yet in this same tick.
        Qt.callLater(() => query.forceActiveFocus())
    }
    function hide() {
        root.open = false
    }
    function toggle() {
        if (root.open) hide(); else show()
    }

    readonly property string mode: {
        const t = query.text
        if (t.startsWith("=")) return "calc"
        if (t.startsWith("?")) return "web"
        if (t.startsWith("$")) return "shell"
        if (t.startsWith("/win")) return "win"
        if (t.startsWith("/f")) return "files"
        if (t.startsWith("/remind")) return "remind"
        if (t.startsWith("/timer")) return "timer"
        if (t.startsWith("/app")) return "app"
        if (t.startsWith("/")) return "actions"
        return "apps"
    }
    readonly property bool isListMode: mode === "actions" || mode === "win" || mode === "files" || mode === "app"

    property int selected: 0
    readonly property var filtered: {
        const q = query.text.trim().toLowerCase()
        const all = Services.Apps.list
        if (!q) return all
        return all.filter(a => a.name.toLowerCase().includes(q) ||
                                a.exec.toLowerCase().includes(q))
    }

    // ---------- /actions ----------
    readonly property var actionsList: [
        { label: "Заблокировать", run: () => Quickshell.execDetached(["qs", "-c", "dotline", "ipc", "call", "lock", "lock"]) },
        { label: "Настройки", run: () => Quickshell.execDetached(["qs", "-c", "dotline", "ipc", "call", "settings", "toggle"]) },
        { label: "Быстрые настройки", run: () => Quickshell.execDetached(["qs", "-c", "dotline", "ipc", "call", "quicksettings", "toggle"]) },
        { label: "Телефон", run: () => Quickshell.execDetached(["qs", "-c", "dotline", "ipc", "call", "phone", "toggle"]) },
        { label: "Медиа", run: () => Quickshell.execDetached(["qs", "-c", "dotline", "ipc", "call", "media", "toggle"]) },
        { label: "Не беспокоить", run: () => Quickshell.execDetached(["qs", "-c", "dotline", "ipc", "call", "dnd", "toggle"]) },
        { label: "Режим: игра", run: () => Quickshell.execDetached(["qs", "-c", "dotline", "ipc", "call", "modes", "set", "game"]) },
        { label: "Режим: фокус", run: () => Quickshell.execDetached(["qs", "-c", "dotline", "ipc", "call", "modes", "set", "focus"]) },
        { label: "Режим: презентация", run: () => Quickshell.execDetached(["qs", "-c", "dotline", "ipc", "call", "modes", "set", "presentation"]) },
        { label: "Режим: обычный", run: () => Quickshell.execDetached(["qs", "-c", "dotline", "ipc", "call", "modes", "set", "normal"]) },
        { label: "Помодоро: старт/стоп", run: () => Services.Pomodoro.toggle() },
        { label: "Шпаргалка клавиш", run: () => Quickshell.execDetached(["qs", "-c", "dotline", "ipc", "call", "keys", "toggle"]) },
        { label: "Тема: авто", run: () => Quickshell.execDetached(["dotline-theme", "auto"]) },
        { label: "Тема: тёмная", run: () => Quickshell.execDetached(["dotline-theme", "dark"]) },
        { label: "Тема: светлая", run: () => Quickshell.execDetached(["dotline-theme", "light"]) },
        { label: "Случайные обои", run: () => Quickshell.execDetached(["dotline-wallpaper", "random"]) },
    ]
    readonly property var filteredActions: {
        if (mode !== "actions") return []
        const q = query.text.slice(1).trim().toLowerCase()
        if (!q) return root.actionsList
        return root.actionsList.filter(a => a.label.toLowerCase().includes(q))
    }

    // ---------- /win ----------
    readonly property var filteredWindows: {
        if (mode !== "win") return []
        const q = query.text.slice(4).trim().toLowerCase()
        return Services.Niri.windows
            .filter(w => !q || (w.title ?? "").toLowerCase().includes(q) ||
                               (w.app_id ?? "").toLowerCase().includes(q))
            .map(w => ({
                label: (w.title || w.app_id || ("#" + w.id)) + (w.is_focused ? "  ·  текущее" : ""),
                run: () => Services.Niri.focusWindow(w.id),
            }))
    }

    // ---------- /f (files) ----------
    readonly property string filesQuery: mode === "files" ? query.text.slice(2).trim() : ""
    property var fileResults: []
    onFilesQueryChanged: {
        if (!filesQuery) { fileResults = []; return }
        filesDebounce.restart()
    }
    Timer {
        id: filesDebounce
        interval: 250
        onTriggered: {
            if (fileProc.running) fileProc.running = false
            fileProc.command = ["fd", "--max-results", "30", "--", root.filesQuery, Quickshell.env("HOME")]
            fileProc.running = true
        }
    }
    Process {
        id: fileProc
        stdout: StdioCollector {
            onStreamFinished: root.fileResults = text.split("\n").map(s => s.trim()).filter(s => s.length > 0)
        }
    }
    readonly property var filteredFiles: {
        if (mode !== "files") return []
        const home = Quickshell.env("HOME")
        return fileResults.map(p => ({
            label: p.startsWith(home) ? ("~" + p.slice(home.length)) : p,
            run: () => Quickshell.execDetached(["xdg-open", p]),
        }))
    }

    // ---------- /app (pacman + AUR + Flathub) ----------
    readonly property string appQuery: mode === "app" ? query.text.slice(4).trim() : ""
    property var appResults: []
    onAppQueryChanged: {
        if (!appQuery) { appResults = []; return }
        appDebounce.restart()
    }
    Timer {
        id: appDebounce
        interval: 250
        onTriggered: {
            if (appProc.running) appProc.running = false
            appProc.command = [Quickshell.env("DOTLINE_ROOT") + "/scripts/app", "search", root.appQuery]
            appProc.running = true
        }
    }
    Process {
        id: appProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.appResults = JSON.parse(text)
                } catch (e) {
                    root.appResults = []
                }
            }
        }
    }
    function appSourceTag(source) {
        if (source === "pacman") return "P"
        if (source === "aur") return "A"
        if (source === "flatpak") return "F"
        return "?"
    }
    readonly property var filteredApps: {
        if (mode !== "app") return []
        return appResults.map(r => ({
            label: "[" + appSourceTag(r.source) + "] " + r.name + (r.description ? " — " + r.description : ""),
            // r.source/r.id came from an AUR search — technically attacker-
            // influenced data (anyone can name an AUR package anything the
            // name rules allow). Passed as sh -c's positional params
            // ($1/$2), never interpolated into the command string itself,
            // so there's no shell-injection path through a crafted name.
            run: () => Quickshell.execDetached(["kitty", "sh", "-c",
                Quickshell.env("DOTLINE_ROOT") + "/scripts/app install \"$1\" \"$2\"; echo; read -p 'Нажмите Enter для выхода…'",
                "dotline-app", r.source, r.id]),
        }))
    }

    readonly property var listItems: {
        if (mode === "actions") return filteredActions
        if (mode === "win") return filteredWindows
        if (mode === "files") return filteredFiles
        if (mode === "app") return filteredApps
        return []
    }

    // ---------- =calc ----------
    readonly property string calcExpr: mode === "calc" ? query.text.slice(1).trim() : ""
    property string calcResult: ""
    onCalcExprChanged: {
        if (!calcExpr) { calcResult = ""; return }
        calcDebounce.restart()
    }
    Timer {
        id: calcDebounce
        interval: 250
        onTriggered: {
            if (calcProc.running) calcProc.running = false
            calcProc.command = ["qalc", "-t", root.calcExpr]
            calcProc.running = true
        }
    }
    Process {
        id: calcProc
        stdout: StdioCollector {
            onStreamFinished: root.calcResult = text.trim()
        }
    }

    // ---------- ?web / $shell ----------
    readonly property string webQuery: mode === "web" ? query.text.slice(1).trim() : ""
    readonly property string shellCmd: mode === "shell" ? query.text.slice(1).trim() : ""

    // ---------- /remind <срок> <текст> / /timer <срок> ----------
    // "10m", "1h30m", "90s" — hours/minutes/seconds, any subset, in that
    // order; not a full natural-language parser on purpose, this is meant
    // to be typed quickly, not read like a sentence.
    function parseDuration(s) {
        const m = /^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$/.exec(s.trim())
        if (!m || (!m[1] && !m[2] && !m[3])) return null
        return (parseInt(m[1] || "0", 10) * 3600) +
               (parseInt(m[2] || "0", 10) * 60) +
               parseInt(m[3] || "0", 10)
    }
    readonly property string remindRest: mode === "remind" ? query.text.slice(7).trim() : ""
    readonly property string timerRest: mode === "timer" ? query.text.slice(6).trim() : ""
    readonly property var remindParsed: {
        if (mode !== "remind") return null
        const sp = remindRest.indexOf(" ")
        if (sp < 0) return null
        const seconds = parseDuration(remindRest.slice(0, sp))
        const label = remindRest.slice(sp + 1).trim()
        return (seconds !== null && label.length > 0) ? { seconds, label } : null
    }
    readonly property var timerParsed: {
        if (mode !== "timer") return null
        const seconds = parseDuration(timerRest)
        return seconds !== null ? { seconds } : null
    }

    // Single entry point for Enter (keyboard) — list-item clicks call
    // `.run()` directly, everything else funnels through here so there's
    // one place that decides what "activate" means per mode.
    function activate() {
        if (mode === "calc") {
            if (calcResult) Quickshell.execDetached(["wl-copy", "--", calcResult])
        } else if (mode === "web") {
            if (webQuery) Quickshell.execDetached(["xdg-open", "https://duckduckgo.com/?q=" + encodeURIComponent(webQuery)])
        } else if (mode === "shell") {
            if (shellCmd) Quickshell.execDetached(["kitty", "sh", "-c", shellCmd])
        } else if (mode === "remind") {
            if (remindParsed) Services.Reminders.add(remindParsed.seconds, remindParsed.label)
        } else if (mode === "timer") {
            if (timerParsed) Services.Reminders.add(timerParsed.seconds, "Таймер")
        } else if (isListMode) {
            if (selected < listItems.length) listItems[selected].run()
        } else if (mode === "apps") {
            if (selected < filtered.length) Services.Apps.launch(filtered[selected])
        }
        hide()
    }

    visible: open
    enabled: open

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Dotline.Theme.surface.r, Dotline.Theme.surface.g, Dotline.Theme.surface.b, 0.55)
        MouseArea { anchors.fill: parent; onClicked: root.hide() }
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 150
        spacing: 44

        Components.Pill {
            anchors.horizontalCenter: parent.horizontalCenter
            paddingH: 26
            implicitWidth: 640

            Rectangle {
                width: 24; height: 24; radius: 12
                anchors.verticalCenter: parent.verticalCenter
                color: "transparent"
                border.width: 2.5
                border.color: Dotline.Theme.muted
                Rectangle {
                    width: 2.5; height: 9
                    rotation: 45
                    color: Dotline.Theme.muted
                    x: 20; y: 18
                }
            }
            TextInput {
                id: query
                width: 560
                anchors.verticalCenter: parent.verticalCenter
                color: Dotline.Theme.ink
                font.family: Dotline.Theme.fontUi
                font.pixelSize: 22
                clip: true

                Text {
                    visible: query.text.length === 0
                    text: "Поиск · = ? $ /win /f /app /"
                    color: Dotline.Theme.muted
                    font: query.font
                }

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        root.hide(); event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.activate()
                        event.accepted = true
                        return
                    }
                    if (!root.isListMode && root.mode !== "apps") return // no navigation for calc/web/shell
                    const n = root.isListMode ? root.listItems.length : root.filtered.length
                    if (event.key === Qt.Key_Down || event.key === Qt.Key_Right) {
                        if (n > 0) root.selected = (root.selected + 1) % n
                        event.accepted = true
                    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Left) {
                        if (n > 0) root.selected = (root.selected - 1 + n) % n
                        event.accepted = true
                    }
                }
                onTextChanged: root.selected = 0
            }
        }

        // ---------- calculator ----------
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.mode === "calc"
            text: root.calcResult || (root.calcExpr ? "…" : "")
            color: Dotline.Theme.ink
            font.family: Dotline.Theme.fontDot
            font.pixelSize: 32
            font.weight: Font.ExtraBold
        }

        // ---------- web search preview ----------
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.mode === "web"
            text: root.webQuery ? ("Найти «" + root.webQuery + "» в DuckDuckGo") : "Введите запрос"
            color: Dotline.Theme.muted
            font.family: Dotline.Theme.fontUi
            font.pixelSize: 16
        }

        // ---------- shell command preview ----------
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.mode === "shell"
            text: root.shellCmd ? ("$ " + root.shellCmd) : "Введите команду"
            color: Dotline.Theme.ink
            font.family: Dotline.Theme.fontMono
            font.pixelSize: 16
        }

        // ---------- /remind, /timer preview ----------
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.mode === "remind"
            text: root.remindParsed
                ? ("Напомнить через " + root.remindRest.slice(0, root.remindRest.indexOf(" ")) + ": " + root.remindParsed.label)
                : "/remind 10m текст"
            color: root.remindParsed ? Dotline.Theme.ink : Dotline.Theme.muted
            font.family: Dotline.Theme.fontUi
            font.pixelSize: 15
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.mode === "timer"
            text: root.timerParsed ? ("Таймер на " + root.timerRest) : "/timer 25m"
            color: root.timerParsed ? Dotline.Theme.ink : Dotline.Theme.muted
            font.family: Dotline.Theme.fontUi
            font.pixelSize: 15
        }

        // ---------- actions / windows / files: one plain text list ----------
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.isListMode
            spacing: 4
            width: 420

            Repeater {
                model: root.listItems
                delegate: Rectangle {
                    id: listRow
                    required property var modelData
                    required property int index
                    width: parent ? parent.width : 420
                    height: 44
                    radius: 14
                    color: listRow.index === root.selected ? Dotline.Theme.surfaceHigh : "transparent"

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        elide: Text.ElideMiddle
                        text: listRow.modelData.label
                        color: Dotline.Theme.ink
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 15
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { listRow.modelData.run(); root.hide() }
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.listItems.length === 0
                text: root.mode === "files" && !root.filesQuery ? "Введите часть имени файла"
                    : root.mode === "app" && !root.appQuery ? "Введите название пакета"
                    : "Ничего не нашлось"
                color: Dotline.Theme.muted
                font.family: Dotline.Theme.fontUi
                font.pixelSize: 16
            }
        }

        // ---------- apps ----------
        Grid {
            anchors.horizontalCenter: parent.horizontalCenter
            columns: root.columns
            spacing: 34
            visible: root.mode === "apps" && root.filtered.length > 0

            Repeater {
                model: root.mode === "apps" ? root.filtered : []
                delegate: Column {
                    id: cell
                    required property var modelData
                    required property int index
                    spacing: 10
                    width: root.cellSize

                    Components.Circle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        diameter: 96
                        interactive: true
                        tint: cell.index === root.selected ? Dotline.Theme.ink : Dotline.Theme.surface

                        Image {
                            id: icon
                            anchors.centerIn: parent
                            width: 40; height: 40
                            source: cell.modelData.icon ? ("image://icon/" + cell.modelData.icon) : ""
                            visible: status === Image.Ready
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: icon.status !== Image.Ready
                            text: cell.modelData.name.charAt(0).toUpperCase()
                            color: parent.contentColor
                            font.family: Dotline.Theme.fontUi
                            font.pixelSize: 30
                        }

                        onClicked: {
                            Services.Apps.launch(cell.modelData)
                            root.hide()
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: root.cellSize
                        horizontalAlignment: Text.AlignHCenter
                        text: cell.modelData.name
                        color: Dotline.Theme.ink
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 14
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.mode === "apps" && root.filtered.length === 0
            text: "Ничего не нашлось"
            color: Dotline.Theme.muted
            font.family: Dotline.Theme.fontUi
            font.pixelSize: 16
        }
    }
}
