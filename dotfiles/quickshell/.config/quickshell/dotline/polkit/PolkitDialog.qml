import QtQuick
import "../" as Dotline
import "../components" as Components

// dotline — the polkit prompt (pkexec, package installs, …), driven
// entirely by Quickshell.Services.Polkit's PolkitAgent/AuthFlow (verified
// against the real docs at quickshell.org/docs — every property and
// function name below is quoted from there, not guessed).
//
// No FaceAuth.qml/faceauthd socket involved here on purpose: polkit's own
// PAM stack (system/etc/pam.d/polkit-1) already runs faceauth-auth as
// root, the same direct-camera path sudo uses, before pam_unix ever asks
// for a password. So when face recognition succeeds, this dialog's flow
// typically completes successfully without `isResponseRequired` ever
// becoming true — the password field below only appears once PAM falls
// through to pam_unix. There's no per-frame "looking for your face"
// signal to show during that window (PAM doesn't expose pam_exec's
// internal state), so this just shows a plain "Проверка…" until either
// a password is asked for or the request completes.
Item {
    id: root

    required property var agent  // PolkitAgent instance, from shell.qml
    readonly property var flow: agent.flow

    visible: agent.isActive

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Dotline.Theme.surface.r, Dotline.Theme.surface.g, Dotline.Theme.surface.b, 0.45)
        MouseArea { anchors.fill: parent; onClicked: {} }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 560
        radius: Dotline.Theme.radius * 1.6
        color: Dotline.Theme.surface
        implicitHeight: col.implicitHeight + 68

        Behavior on color { ColorAnimation { duration: 900 } }

        Column {
            id: col
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 34
            spacing: 18

            Text {
                text: "Нужно подтверждение"
                color: Dotline.Theme.ink
                font.family: Dotline.Theme.fontDot
                font.pixelSize: 30
                font.weight: Font.ExtraBold
            }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: root.flow ? root.flow.message : ""
                color: Dotline.Theme.ink
                font.family: Dotline.Theme.fontUi
                font.pixelSize: 16
            }
            Text {
                visible: root.flow && root.flow.actionId.length > 0
                text: root.flow ? root.flow.actionId : ""
                color: Dotline.Theme.muted
                font.family: Dotline.Theme.fontMono
                font.pixelSize: 12
            }

            Text {
                visible: root.flow && root.flow.supplementaryMessage.length > 0
                width: parent.width
                wrapMode: Text.Wrap
                text: root.flow ? root.flow.supplementaryMessage : ""
                color: (root.flow && root.flow.supplementaryIsError) ? Dotline.Theme.accent : Dotline.Theme.muted
                font.family: Dotline.Theme.fontUi
                font.pixelSize: 14
            }

            Text {
                visible: root.flow && !root.flow.isResponseRequired && !root.flow.isCompleted
                text: "Проверка…"
                color: Dotline.Theme.muted
                font.family: Dotline.Theme.fontUi
                font.pixelSize: 15
            }

            Rectangle {
                width: parent.width
                height: 52
                radius: 26
                color: Dotline.Theme.surfaceHigh
                visible: root.flow && root.flow.isResponseRequired

                TextInput {
                    id: password
                    anchors.fill: parent
                    anchors.margins: 4
                    horizontalAlignment: TextInput.AlignHCenter
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: (root.flow && root.flow.responseVisible) ? TextInput.Normal : TextInput.Password
                    color: Dotline.Theme.ink
                    font.family: Dotline.Theme.fontUi
                    font.pixelSize: 16

                    Text {
                        anchors.centerIn: parent
                        visible: password.text.length === 0 && !password.activeFocus
                        text: root.flow ? root.flow.inputPrompt : ""
                        color: Dotline.Theme.muted
                        font: password.font
                    }

                    onAccepted: if (root.flow) root.flow.submit(password.text)
                }

                // Password field appears fresh on each new prompt (e.g. a
                // retry after a wrong one).
                Connections {
                    target: root.flow
                    function onIsResponseRequiredChanged() {
                        password.text = ""
                        if (root.flow.isResponseRequired) password.forceActiveFocus()
                    }
                }
            }

            Row {
                anchors.right: parent.right
                spacing: 10
                Rectangle {
                    width: 110; height: 44; radius: 22
                    color: Dotline.Theme.surfaceHigh
                    Text { anchors.centerIn: parent; text: "Отмена"; color: Dotline.Theme.ink; font.family: Dotline.Theme.fontUi; font.pixelSize: 15 }
                    MouseArea { anchors.fill: parent; onClicked: if (root.flow) root.flow.cancelAuthenticationRequest() }
                }
                Rectangle {
                    width: 150; height: 44; radius: 22
                    color: Dotline.Theme.ink
                    visible: root.flow && root.flow.isResponseRequired
                    Text { anchors.centerIn: parent; text: "Подтвердить"; color: Dotline.Theme.surface; font.family: Dotline.Theme.fontUi; font.pixelSize: 15 }
                    MouseArea { anchors.fill: parent; onClicked: if (root.flow) root.flow.submit(password.text) }
                }
            }
        }
    }
}
