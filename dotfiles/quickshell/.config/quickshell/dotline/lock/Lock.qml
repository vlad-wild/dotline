import QtQuick
import Quickshell
import Quickshell.Io
import "../" as Dotline
import "../Glyphs.js" as Glyphs
import "../components" as Components
import "../services" as Services

// dotline — the lock screen (see the mock-up's #lock). Two
// independent unlock paths race each other, same as the plan describes:
// (1) FaceAuth.verify("lock") talks straight to faceauthd over its socket;
// (2) a password typed into the field below goes through PAM as
// "qs-lock" (see system/etc/pam.d/qs-lock — pam_unix only, deliberately
// no faceauth-auth line, so the camera is never asked twice for the same
// unlock). Whichever succeeds first unlocks.
//
// PamContext here is the other real guess in this file (alongside the
// WlSessionLock/WlSessionLockSurface this sits inside, from shell.qml):
// Quickshell doing a PAM conversation from QML is a documented feature,
// but I don't have its exact property/signal names to check against.
Item {
    id: root
    // The session-lock protocol itself is what should give this exclusive
    // keyboard focus while locked (that's its whole purpose) — `focus:
    // true` just makes sure this Item is the one inside the surface that
    // claims it.
    focus: true

    signal unlocked()

    readonly property bool faceFailed: !Services.FaceAuth.scanning && _faceTried && !_faceOk
    property bool _faceTried: false
    property bool _faceOk: false

    property string wallpaperPath: ""
    // Same reasoning as Theme.qml's _stateHome: Quickshell.env()'s 2-arg
    // default isn't something to assume works, so this is spelled out.
    readonly property string _stateHome: {
        const v = Quickshell.env("XDG_STATE_HOME")
        return (v && v.length > 0) ? v : (Quickshell.env("HOME") + "/.local/state")
    }
    FileView {
        path: root._stateHome + "/dotline/wallpaper"
        onLoaded: root.wallpaperPath = text().trim()
    }

    function tryFace() {
        if (Services.FaceAuth.scanning) return
        root._faceTried = true
        root._faceOk = false
        Services.FaceAuth.verify("lock")
    }

    Component.onCompleted: tryFace()

    Connections {
        target: Services.Pam
        function onSuccess() { root.unlocked() }
        function onFailed() {
            password.text = ""
            shake.start()
        }
    }

    Connections {
        target: Services.FaceAuth
        function onSuccess() {
            root._faceOk = true
            root.unlocked()
        }
        function onFailed(outcome, reason) {
            root._faceOk = false
            // "skipped" (disabled/no model/lid closed/remote session) isn't
            // a failed attempt to react to with a shake — just fall
            // through to the password field quietly.
        }
    }

    // Wake/unlock-prompt/keypress can all ask again, but not more than
    // once every 10s (see the plan's lock-screen note).
    property real _lastTryMs: 0
    function nudgeFace() {
        const now = Date.now()
        if (now - root._lastTryMs < 10000) return
        root._lastTryMs = now
        tryFace()
    }

    Image {
        anchors.fill: parent
        source: root.wallpaperPath ? "file://" + root.wallpaperPath : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        // No blur: Qt6's blur effect module (MultiEffect vs
        // Qt5Compat.GraphicalEffects.FastBlur) isn't something to guess
        // the right import for blind — a plain dim overlay below is the
        // safe version of the mock-up's blurred backdrop.
    }
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Dotline.Theme.surface.r, Dotline.Theme.surface.g, Dotline.Theme.surface.b, 0.55)
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: root.nudgeFace()
        onClicked: root.nudgeFace()
    }
    Keys.onPressed: root.nudgeFace()

    readonly property var _days: ["ВС", "ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ"]
    readonly property var _months: ["ЯНВ.", "ФЕВР.", "МАРТА", "АПР.", "МАЯ", "ИЮНЯ", "ИЮЛЯ", "АВГ.", "СЕНТ.", "ОКТ.", "НОЯБ.", "ДЕК."]
    property var _now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: root._now = new Date() }

    Text {
        x: 78; y: 92
        text: Qt.formatDateTime(root._now, "hh:mm")
        color: Dotline.Theme.ink
        font.family: Dotline.Theme.fontDot
        font.pixelSize: 184
        font.weight: Font.ExtraBold
    }
    Text {
        x: 84; y: 92 + 184 + 24
        text: root._days[root._now.getDay()] + ", " + root._now.getDate() + " " + root._months[root._now.getMonth()]
        color: Dotline.Theme.ink
        font.family: Dotline.Theme.fontDot
        font.pixelSize: 34
        font.weight: Font.ExtraBold
    }

    // Face + password, bottom-center (see the mock-up's .lk-face).
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 70
        spacing: 14
        width: 540

        Components.Circle {
            id: faceCircle
            anchors.horizontalCenter: parent.horizontalCenter
            diameter: 136
            tint: Dotline.Theme.surface

            Components.DotMatrix {
                anchors.centerIn: parent
                pattern: Glyphs.face
                cell: 6.6
                dotRadius: 2.4
                color: root._faceOk ? Dotline.Theme.ink
                     : Services.FaceAuth.faceVisible ? Dotline.Theme.ink
                     : Dotline.Theme.muted
            }

            SequentialAnimation on scale {
                running: Services.FaceAuth.scanning && !root._faceOk
                loops: Animation.Infinite
                NumberAnimation { to: 1.04; duration: 650; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 650; easing.type: Easing.InOutSine }
            }
            SequentialAnimation {
                id: shake
                PropertyAnimation { target: faceCircle; property: "x"; from: 0; to: -8; duration: 60 }
                PropertyAnimation { target: faceCircle; property: "x"; from: -8; to: 8; duration: 60 }
                PropertyAnimation { target: faceCircle; property: "x"; from: 8; to: 0; duration: 60 }
            }
            Connections {
                target: Services.FaceAuth
                function onFailed(outcome, reason) {
                    if (outcome === "no_match" || outcome === "too_dark") shake.start()
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Services.FaceAuth.scanning ? "Смотрю на вас…"
                : root._faceOk ? "Это вы"
                : root.faceFailed ? "Не узнал. Введите пароль"
                : "Коснитесь, чтобы начать"
            color: Dotline.Theme.muted
            font.family: Dotline.Theme.fontUi
            font.pixelSize: 17
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 360; height: 56
            radius: 28
            color: Dotline.Theme.surface
            visible: root.faceFailed || password.text.length > 0 || password.activeFocus

            TextInput {
                id: password
                anchors.fill: parent
                anchors.margins: 4
                horizontalAlignment: TextInput.AlignHCenter
                verticalAlignment: TextInput.AlignVCenter
                echoMode: TextInput.Password
                color: Dotline.Theme.ink
                font.family: Dotline.Theme.fontUi
                font.pixelSize: 18

                Text {
                    anchors.centerIn: parent
                    visible: password.text.length === 0 && !password.activeFocus
                    text: "Пароль"
                    color: Dotline.Theme.muted
                    font: password.font
                }

                onAccepted: Services.Pam.unlock(password.text)
                onActiveFocusChanged: if (activeFocus) Services.Pam.start()
            }
        }
    }
}
