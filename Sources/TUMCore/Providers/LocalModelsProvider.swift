import Foundation

public struct LocalModelsProvider: UsageProvider {
    public let id: ProviderID = .localModels
    private let config: LocalModelsConfig

    public init(config: LocalModelsConfig) {
        self.config = config
    }

    public func fetch() async -> ProviderSnapshot {
        let hosts = config.hosts.filter {
            !$0.sshTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !hosts.isEmpty else {
            return .unavailable(
                .localModels,
                state: .needsAuth,
                message: "Add a machine in Settings.",
                planLabel: "Local"
            )
        }

        let reports = await withTaskGroup(of: (Int, Result<UsageMeter, Error>).self) { group in
            for (index, host) in hosts.enumerated() {
                group.addTask {
                    do {
                        let meter = try await Self.meter(for: host)
                        return (index, .success(meter))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var collected: [(Int, Result<UsageMeter, Error>)] = []
            for await item in group {
                collected.append(item)
            }
            return collected.sorted { $0.0 < $1.0 }
        }

        var meters: [UsageMeter] = []
        var loadedNames: [String] = []
        var failures: [String] = []
        for (index, result) in reports {
            let host = hosts[index]
            switch result {
            case .success(let meter):
                meters.append(meter)
                if let model = meter.resetDescription, model != "Nothing loaded" {
                    loadedNames.append(model)
                }
            case .failure(let error):
                let name = Self.displayName(for: host)
                failures.append("\(name): \(error.localizedDescription)")
                meters.append(
                    UsageMeter(
                        id: host.id.uuidString,
                        title: name,
                        remainingFraction: 0,
                        resetDescription: error.localizedDescription,
                        reading: "—"
                    )
                )
            }
        }

        let liveCount = meters.filter { $0.reading != "—" }.count
        return ProviderSnapshot(
            id: .localModels,
            planLabel: loadedNames.isEmpty ? "Nothing loaded" : loadedNames.joined(separator: " · "),
            state: liveCount > 0 ? .live : .offline,
            meters: meters,
            detailSummary: "Loaded models",
            message: failures.isEmpty ? nil : failures.joined(separator: " "),
            fullWidth: hosts.count > 1
        )
    }

    static func meter(for host: LocalModelHostConfig) async throws -> UsageMeter {
        let report = try await probe(host: host)
        let name = displayName(for: host)
        let model = report.model?.trimmingCharacters(in: .whitespacesAndNewlines)
        let loaded = (model?.isEmpty == false) ? model! : "Nothing loaded"
        let fractionFree: Double = {
            guard report.totalBytes > 0 else { return 1 }
            return 1 - (Double(report.modelBytes) / Double(report.totalBytes))
        }()
        let footnote = report.totalBytes > 0 ? "of \(memory(report.totalBytes))" : nil
        return UsageMeter(
            id: host.id.uuidString,
            title: name,
            remainingFraction: fractionFree,
            resetDescription: loaded,
            footnote: footnote,
            reading: memory(report.modelBytes)
        )
    }

    static func probe(host: LocalModelHostConfig) async throws -> LocalModelReport {
        let target = host.sshTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard target.range(of: #"^[A-Za-z0-9._@:-]+$"#, options: .regularExpression) != nil else {
            throw ProviderError.notConfigured("SSH target has characters ssh will not accept.")
        }
        let ssh = "/usr/bin/ssh"
        guard FileManager.default.isExecutableFile(atPath: ssh) else {
            throw ProviderError.notConfigured("ssh is not available.")
        }

        let statusURL = try Self.validatedStatusURL(host.statusURL)
        let processName = try Self.validatedProcessName(host.processName)
        var remoteCommand = ["python3", "-"]
        if !statusURL.isEmpty || !processName.isEmpty {
            var env = ["env"]
            if !statusURL.isEmpty { env.append("TUM_STATUS_URL=\(statusURL)") }
            if !processName.isEmpty { env.append("TUM_PROCESS_NAME=\(processName)") }
            remoteCommand = env + remoteCommand
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ssh)
        process.arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "-o", "StrictHostKeyChecking=accept-new",
            target,
        ] + remoteCommand
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        try process.run()
        input.fileHandleForWriting.write(Data(Self.probeScript.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()

        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ProviderError.http(
                Int(process.terminationStatus),
                detail.isEmpty ? "SSH failed" : String(detail.prefix(180))
            )
        }
        return try LocalModelReport.parse(stdout)
    }

    static func validatedStatusURL(_ raw: String) throws -> String {
        let url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty { return "" }
        let pattern = #"^http://(127\.0\.0\.1|localhost)(:[0-9]{1,5})?(/[A-Za-z0-9._~/-]*)?$"#
        guard url.range(of: pattern, options: .regularExpression) != nil else {
            throw ProviderError.notConfigured("Status URL must be an http://127.0.0.1 or http://localhost address on that machine.")
        }
        return url
    }

    static func validatedProcessName(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "" }
        guard name.range(of: #"^[A-Za-z0-9._-]{1,64}$"#, options: .regularExpression) != nil else {
            throw ProviderError.notConfigured("Process name can only use letters, numbers, dots, dashes, and underscores.")
        }
        return name
    }

    static func displayName(for host: LocalModelHostConfig) -> String {
        let label = host.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty { return label }
        return host.sshTarget
    }

    static func memory(_ bytes: Int) -> String {
        let gigabytes = Double(bytes) / 1_073_741_824
        let pattern = (gigabytes >= 100 || abs(gigabytes - gigabytes.rounded()) < 0.05) ? "%.0f GB" : "%.1f GB"
        return String(format: pattern, locale: Locale(identifier: "en_US_POSIX"), gigabytes)
    }

    static let probeScript = """
    import json, os, urllib.request

    def http_json(url):
        try:
            with urllib.request.urlopen(url, timeout=2) as response:
                return json.load(response)
        except Exception:
            return None

    model = None
    model_bytes = None
    source = None

    ps = http_json("http://127.0.0.1:11434/api/ps")
    if isinstance(ps, dict) and ps.get("models"):
        names = []
        total = 0
        for item in ps["models"]:
            name = item.get("name") or item.get("model")
            if name:
                names.append(name)
            total += int(item.get("size_vram") or item.get("size") or 0)
        if names:
            model = ", ".join(names)
            model_bytes = total
            source = "ollama"

    status_url = os.environ.get("TUM_STATUS_URL") or ""
    if model is None and status_url:
        health = http_json(status_url)
        if isinstance(health, dict) and isinstance(health.get("model"), str) and health.get("model"):
            model = health["model"]
            source = "http"

    process_name = os.environ.get("TUM_PROCESS_NAME") or ""
    total_bytes = None
    available_bytes = None
    if os.path.exists("/proc/meminfo"):
        info = {}
        for line in open("/proc/meminfo"):
            key, value = line.split(":", 1)
            if key in ("MemTotal", "MemAvailable"):
                info[key] = int(value.split()[0]) * 1024
        total_bytes = info.get("MemTotal")
        available_bytes = info.get("MemAvailable")
        if model_bytes is None and process_name:
            best = 0
            for entry in os.listdir("/proc"):
                if not entry.isdigit():
                    continue
                try:
                    command = open(f"/proc/{entry}/cmdline", "rb").read().replace(b"\\0", b" ").decode("utf-8", "replace")
                    status = open(f"/proc/{entry}/status").read()
                except OSError:
                    continue
                if process_name not in command:
                    continue
                rss = 0
                for row in status.splitlines():
                    if row.startswith("VmRSS:"):
                        rss = int(row.split()[1]) * 1024
                if rss > best:
                    best = rss
            if best:
                model_bytes = best
                source = source or "process"
    else:
        import subprocess
        total_bytes = int(subprocess.check_output(["sysctl", "-n", "hw.memsize"]).strip())

    print(json.dumps({
        "ok": True,
        "model": model,
        "modelBytes": model_bytes or 0,
        "totalBytes": total_bytes or 0,
        "availableBytes": available_bytes,
        "source": source,
    }))
    """
}

struct LocalModelReport: Equatable, Sendable {
    var model: String?
    var modelBytes: Int
    var totalBytes: Int

    static func parse(_ data: Data) throws -> LocalModelReport {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.decoding("Machine probe was not JSON")
        }
        let model = json["model"] as? String
        let modelBytes = (json["modelBytes"] as? Int)
            ?? (json["modelBytes"] as? Double).map { Int($0) }
            ?? 0
        let totalBytes = (json["totalBytes"] as? Int)
            ?? (json["totalBytes"] as? Double).map { Int($0) }
            ?? 0
        return LocalModelReport(
            model: model,
            modelBytes: modelBytes,
            totalBytes: totalBytes
        )
    }
}
