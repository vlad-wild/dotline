pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pam

// dotline — the lock screen's password fallback, via PAM service
// "qs-lock" (system/etc/pam.d/qs-lock: pam_unix only, no faceauth-auth —
// see that file's own comment for why).
//
// Verified against the real Quickshell.Services.Pam docs (quickshell.org)
// after an earlier draft of this file guessed both the import path
// (Quickshell.Io — wrong, it's Quickshell.Services.Pam) and the signal
// shapes (onPamMessage/onCompleted took parameters that don't exist on
// the real signals; `message`/`responseRequired` are read as PamContext's
// own properties instead, and completed's result is the PamResult enum).
Singleton {
    id: root

    signal success()
    signal failed()

    property string _pending: ""

    // Called once the password field has focus, so a conversation is
    // ready before Enter is pressed.
    function start() {
        if (!ctx.active) ctx.start()
    }

    // Called on Enter in the password field.
    function unlock(password) {
        root._pending = password
        if (ctx.responseRequired) {
            ctx.respond(password)
        } else if (!ctx.active) {
            ctx.start()
        }
    }

    PamContext {
        id: ctx
        config: "qs-lock"

        onPamMessage: {
            if (responseRequired && root._pending.length > 0) {
                respond(root._pending)
            }
        }
        onCompleted: (result) => {
            if (result === PamResult.Success) root.success(); else root.failed()
        }
    }
}
