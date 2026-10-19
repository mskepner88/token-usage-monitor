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
