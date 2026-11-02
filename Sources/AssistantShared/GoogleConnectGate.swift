import Foundation

/// Decides whether the Google OAuth flow may start. The daemon reads the
/// client id from saved settings and the client secret from `.env`, so OAuth
/// must not start with credentials that only exist in the text fields.
public enum GoogleConnectGate {

    /// Both fields filled in (enables the Save/Connect button).
    public static func canAttempt(clientID: String, secret: String) -> Bool {
        !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// OAuth may start only after the settings save and the secret save both
    /// succeeded, with non-empty id and secret.
    public static func canStart(settingsSaved: Bool, secretSaved: Bool,
                                clientID: String, secret: String) -> Bool {
        settingsSaved && secretSaved && canAttempt(clientID: clientID, secret: secret)
    }

    /// User-facing message when a save failed, nil when both succeeded.
    public static func saveFailureMessage(settingsSaved: Bool, secretSaved: Bool) -> String? {
        switch (settingsSaved, secretSaved) {
        case (true, true): return nil
        case (false, true): return "Couldn't save the client ID. Check that Assistant's background service is running, then try again."
        case (true, false): return "Couldn't save the client secret to the Assistant .env file. Check that the file is writable, then try again."
        case (false, false): return "Couldn't save the Google credentials. Check that Assistant's background service is running, then try again."
        }
    }
}
