import XCTest
@testable import TUMCore

final class LocalModelsParseTests: XCTestCase {
    func testParseLoadedModel() throws {
        let json = """
        {"ok":true,"model":"example:7b","modelBytes":8589934592,"totalBytes":17179869184,"source":"ollama"}
        """.data(using: .utf8)!
        let report = try LocalModelReport.parse(json)
        XCTAssertEqual(report.model, "example:7b")
        XCTAssertEqual(report.modelBytes, 8_589_934_592)
        XCTAssertEqual(report.totalBytes, 17_179_869_184)
    }

    func testParseNullModel() throws {
        let json = """
        {"ok":true,"model":null,"modelBytes":0,"totalBytes":17179869184}
        """.data(using: .utf8)!
        let report = try LocalModelReport.parse(json)
        XCTAssertNil(report.model)
        XCTAssertEqual(report.modelBytes, 0)
        XCTAssertEqual(report.totalBytes, 17_179_869_184)
    }

    func testParseUsedBytes() throws {
        let json = """
        {"ok":true,"model":"Qwen3.8-Flash-Next","modelBytes":73996959744,"totalBytes":130663170048,"availableBytes":45832949760,"usedBytes":84830220288,"source":"http"}
        """.data(using: .utf8)!
        let report = try LocalModelReport.parse(json)
        XCTAssertEqual(report.usedBytes, 84_830_220_288)
        XCTAssertEqual(report.modelBytes, 73_996_959_744)
    }

    func testOlderProbeHasNoUsedBytes() throws {
        let json = """
        {"ok":true,"model":"example:7b","modelBytes":8589934592,"totalBytes":17179869184}
        """.data(using: .utf8)!
        XCTAssertNil(try LocalModelReport.parse(json).usedBytes)
    }

    /// Unified-memory machine (DGX Spark): the bar is the machine's memory in use,
    /// and the model's own GPU memory is a secondary detail.
    func testMeterShowsSystemMemoryWithModelDetail() {
        let host = LocalModelHostConfig(label: "Spark", sshTarget: "user@spark")
        let report = LocalModelReport(
            model: "Qwen3.8-Flash-Next",
            modelBytes: 73_996_959_744,
            totalBytes: 130_663_170_048,
            usedBytes: 84_830_220_288
        )
        let meter = LocalModelsProvider.meter(for: host, report: report)
        XCTAssertEqual(meter.title, "Spark")
        XCTAssertEqual(meter.reading, "79 GB")
        XCTAssertEqual(meter.resetDescription, "Qwen3.8-Flash-Next")
        XCTAssertEqual(meter.footnote, "of 122 GB · model 68.9 GB")
        XCTAssertEqual(meter.remainingFraction, 1 - 84_830_220_288.0 / 130_663_170_048.0, accuracy: 0.0001)
    }

    func testMeterFallsBackToModelBytesWithoutUsedBytes() {
        let host = LocalModelHostConfig(label: "Studio", sshTarget: "user@studio")
        let report = LocalModelReport(model: "example:7b", modelBytes: 8_589_934_592, totalBytes: 17_179_869_184)
        let meter = LocalModelsProvider.meter(for: host, report: report)
        XCTAssertEqual(meter.reading, "8 GB")
        XCTAssertEqual(meter.footnote, "of 16 GB")
        XCTAssertEqual(meter.remainingFraction, 0.5, accuracy: 0.0001)
    }

    func testProbeReadsGPUProcessMemory() {
        XCTAssertTrue(LocalModelsProvider.probeScript.contains("--query-compute-apps=pid,used_memory"))
        XCTAssertTrue(LocalModelsProvider.probeScript.contains("\"usedBytes\""))
    }

    func testMemoryLabels() {
        XCTAssertEqual(LocalModelsProvider.memory(1_610_612_736), "1.5 GB")
        XCTAssertEqual(LocalModelsProvider.memory(8_589_934_592), "8 GB")
        XCTAssertEqual(LocalModelsProvider.memory(17_179_869_184), "16 GB")
        XCTAssertEqual(LocalModelsProvider.memory(137_438_953_472), "128 GB")
    }

    func testRejectsRemoteStatusURL() throws {
        XCTAssertThrowsError(try LocalModelsProvider.validatedStatusURL("http://10.0.0.5/health"))
        XCTAssertEqual(try LocalModelsProvider.validatedStatusURL(""), "")
        XCTAssertEqual(
            try LocalModelsProvider.validatedStatusURL("http://127.0.0.1:8080/health"),
            "http://127.0.0.1:8080/health"
        )
    }

    func testRejectsUnsafeSSHTarget() async {
        let host = LocalModelHostConfig(label: "Bad", sshTarget: "root@spark;id")
        do {
            _ = try await LocalModelsProvider.probe(host: host)
            XCTFail("Expected rejection")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("SSH target"))
        }
    }
}
