import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd

// dotline — the graphical login screen (see the mock-up's "Вход при
// загрузке"). Loaded by greetd via `qs -p /etc/dotline/greeter`
// (system/etc/greetd/{config.toml,niri-greeter.kdl}), as the `greeter`
// system user — which can't read the real user's ~/.config to pull in
// Theme.qml/components/Glyphs.js the way the normal shell does, so this
// file is deliberately self-contained (inlines its own tiny dot-grid face
// and a copy of the palette-reading logic) rather than importing them.
//
// Checked against the real Quickshell.Services.Greetd docs: createSession/
// respond/launch/cancelSession and the authMessage/authFailure/
// readyToLaunch/launched/error signals are exactly as documented there,
// not guessed. What's NOT checked: an actual login attempt on the laptop
// — in particular, that PAM's own faceauth-auth step (system/etc/pam.d/
// greetd) fires silently before authMessage ever asks for a password,
// the same relationship already reasoned through for the polkit dialog.
ShellRoot {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        focusable: true
        color: "transparent"

        // ---------- palette (same contract as the normal shell's Theme.qml,
        // but the root-owned copy lib/palette.sh publishes for exactly this
        // reason — see that file's _palette_publish_for_greeter) ----------
        property color surface: "#1b1b1d"
        property color surfaceHigh: "#2e2e30"
        property color ink: "#f2f2f0"
        property color muted: "#bdbdbd"
        property color accent: "#d71921"

        FileView {
            path: "/var/lib/dotline/palette.json"
            onLoaded: {
                try {
                    const p = JSON.parse(text())
                    surface = p.surface; surfaceHigh = p.surfaceHigh
                    ink = p.on; muted = p.muted; accent = p.accent
                } catch (e) {
                    console.warn("Greeter: palette.json unreadable, using the built-in default:", e)
                }
            }
        }

        Rectangle { anchors.fill: parent; color: surface }

        // ---------- state ----------
        property string stage: "user"       // "user" | "auth" | "launching" | "error"
        property string errorText: ""
        property string promptText: ""
        property bool promptVisible: false
        property bool promptEcho: false

        Greetd {
            id: greetd
            onAuthMessage: (message, error, responseRequired, echoResponse) => {
                promptText = message
                promptVisible = responseRequired
                promptEcho = echoResponse
                stage = "auth"
                if (responseRequired) {
                    password.text = ""
                    Qt.callLater(() => password.forceActiveFocus())
                }
            }
            onAuthFailure: (message) => {
                errorText = message || "Не удалось войти"
                stage = "error"
                password.text = ""
            }
            onReadyToLaunch: {
                stage = "launching"
                // The user's own niri session — their ~/.config/niri/config.kdl
                // already spawns the full dotline shell from there.
                greetd.launch(["niri"])
            }
            onError: (error) => {
                errorText = error
                stage = "error"
            }
        }

        function retry() {
            stage = "user"
            errorText = ""
            username.forceActiveFocus()
        }

        // ---------- clock (plain Text, Matrix Sans Print by family name —
        // no Theme.qml to centralise it here) ----------
        Text {
            x: 78; y: 60
            text: Qt.formatDateTime(new Date(), "hh:mm")
            color: ink
            font.family: "Matrix Sans Print"
            font.pixelSize: 96
            font.weight: Font.ExtraBold
        }

        // ---------- small dot-grid face, same bitmap as Glyphs.js's
        // `face` (copied, not imported — see the file comment) ----------
        Canvas {
            id: faceCanvas
            width: 136; height: 136
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -40
            readonly property var pattern: [
                ".#########.", "#.........#", "#...###...#", "#.........#",
                "#.........#", "#..#...#..#", "#.........#", "#....#....#",
                "#....#....#", "#...##....#", "#.........#", "#..#...#..#",
                "#...###...#", "#.........#", "#.........#", "#....#....#",
                ".#########."
            ]
            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                const cell = 8
                ctx.fillStyle = ink
                for (let y = 0; y < pattern.length; y++) {
                    for (let x = 0; x < pattern[y].length; x++) {
                        if (pattern[y][x] !== "#") continue
                        ctx.beginPath()
                        ctx.arc(x * cell + cell / 2, y * cell + cell / 2, cell * 0.36, 0, Math.PI * 2)
                        ctx.fill()
                    }
                }
            }
            Component.onCompleted: requestPaint()
        }
        onInkChanged: faceCanvas.requestPaint()

        // ---------- username / password ----------
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 140
            spacing: 16
            width: 360

            Rectangle {
                width: parent.width; height: 56; radius: 28
                color: surfaceHigh
                visible: stage === "user"

                TextInput {
                    id: username
                    anchors.fill: parent
                    anchors.margins: 4
                    horizontalAlignment: TextInput.AlignHCenter
                    verticalAlignment: TextInput.AlignVCenter
                    color: ink
                    font.pixelSize: 18
                    focus: true

                    Text {
                        anchors.centerIn: parent
                        visible: username.text.length === 0 && !username.activeFocus
                        text: "Имя пользователя"
                        color: muted
                        font: username.font
                    }
                    onAccepted: if (text.length > 0) greetd.createSession(text)
                }
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                visible: stage === "auth" && promptText.length > 0
                text: promptText
                color: muted
                font.pixelSize: 15
            }
            Rectangle {
                width: parent.width; height: 56; radius: 28
                color: surfaceHigh
                visible: stage === "auth" && promptVisible

                TextInput {
                    id: password
                    anchors.fill: parent
                    anchors.margins: 4
                    horizontalAlignment: TextInput.AlignHCenter
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: promptEcho ? TextInput.Normal : TextInput.Password
                    color: ink
                    font.pixelSize: 18
                    onAccepted: greetd.respond(text)
                }
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: stage === "auth" && !promptVisible
                text: "Проверка…"
                color: muted
                font.pixelSize: 15
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                visible: stage === "error"
                text: errorText
                color: accent
                font.pixelSize: 15
            }
            Rectangle {
                width: 140; height: 44; radius: 22
                anchors.horizontalCenter: parent.horizontalCenter
                color: surfaceHigh
                visible: stage === "error"
                Text { anchors.centerIn: parent; text: "Повторить"; color: ink; font.pixelSize: 15 }
                MouseArea { anchors.fill: parent; onClicked: retry() }
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: stage === "launching"
                text: "Входим…"
                color: muted
                font.pixelSize: 15
            }
        }
    }
}
