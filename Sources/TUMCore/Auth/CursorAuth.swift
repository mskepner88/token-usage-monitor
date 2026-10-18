import Foundation

/// Reads the Cursor IDE session token from local `state.vscdb` (same source community tools use).
public enum CursorAuth {
    public static let secretsAccount = "cursor-session"

    public static var defaultStateDB: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
            )
    }

    public static func resolveAccessToken(
        config: CursorConfig,
        secrets: any SecretStore
    ) throws -> String {
        if let path = config.stateDBPath {
            let expanded = TUMFormatting.expandHome(path)
            if let tok = readAccessToken(from: URL(fileURLWithPath: expanded)), !tok.isEmpty {
                return tok
            }
        }

        if let tok = readAccessToken(from: defaultStateDB), !tok.isEmpty {
            return tok
        }

        if let cookie = try secrets.get(account: config.cookieKeychainAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !cookie.isEmpty {
            // Allow pasting either a raw JWT or a full Cookie header / Workos value.
            if cookie.lowercased().hasPrefix("workoscursorsessiontoken=") {
                return String(cookie.split(separator: "=", maxSplits: 1).last ?? Substring(cookie))
            }
            if cookie.contains("WorkosCursorSessionToken=") {
                for part in cookie.split(separator: ";") {
                    let p = part.trimmingCharacters(in: .whitespaces)
                    if p.hasPrefix("WorkosCursorSessionToken=") {
                        return String(p.dropFirst("WorkosCursorSessionToken=".count))
                    }
                }
            }
            return cookie
        }

        throw ProviderError.missingCredentials(
            "Cursor not signed in. Open the Cursor app once, or paste a session cookie in Settings."
        )
    }

    public static func workosCookie(from accessToken: String) -> String {
        // Dashboard cookie is `userId::jwt` URL-encoded when JWT has a `sub` claim.
        if let sub = jwtSubject(accessToken) {
            let raw = "\(sub)::\(accessToken)"
            let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
            return "WorkosCursorSessionToken=\(encoded)"
        }
        return "WorkosCursorSessionToken=\(accessToken)"
    }

    private static func readAccessToken(from dbURL: URL) -> String? {
        guard FileManager.default.fileExists(atPath: dbURL.path) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            dbURL.path,
            "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1;",
        ]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty == false) ? text : nil
    }

    private static func jwtSubject(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - b64.count % 4) % 4
        if pad > 0 { b64 += String(repeating: "=", count: pad) }
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String
        else { return nil }
        return sub
    }
}
