import XCTest
@testable import MacMemCore

final class TopCompressedSourceTests: XCTestCase {

    // MARK: - parse(_:)

    private let sampleOutput = """
Processes: 412 total, 4 running, 408 sleeping, 2547 threads
Load Avg: 2.45, 2.84, 2.91
CPU usage: 12.34% user, 5.67% sys, 82.0% idle
SharedLibs: 1234M resident, 567M data, 890M linkedit.
MemRegions: 12345 total, 4.5G resident, 1.2G private, 3.4G shared.
PhysMem: 64G used (8.0G wired, 32G compressor), 128M unused.
VM: 5T vsize, 987M framework vsize, 12345(0) swapins, 6789(0) swapouts.
Networks: packets: 1234/567K in, 890/123K out.
Disks: 9876/456M read, 5432/789M written.

PID    CMPRS
71945  18G
64969  2543M
99536  102M
99941  4816K
12345  0B
"""

    func testParseSkipsSummaryBlockAndReadsTable() {
        let result = TopCompressedSource.parse(sampleOutput)
        XCTAssertEqual(result[71945], 18 * 1_073_741_824, "18G should be 18 * 1_073_741_824 bytes")
        XCTAssertEqual(result[64969], 2543 * 1_048_576,   "2543M should be 2543 * 1_048_576 bytes")
        XCTAssertEqual(result[99536], 102 * 1_048_576,    "102M should be 102 * 1_048_576 bytes")
        XCTAssertEqual(result[99941], 4816 * 1024,        "4816K should be 4816 * 1024 bytes")
        XCTAssertEqual(result[12345], 0,                  "0B should be 0 bytes")
    }

    func testParseHandlesTrailingSpacesOnRows() {
        let output = "PID    CMPRS\n99536  102M  \n"
        let result = TopCompressedSource.parse(output)
        XCTAssertEqual(result[99536], 102 * 1_048_576)
    }

    func testParseIgnoresJunkAndBlankLines() {
        let output = """
Processes: junk line
PID    CMPRS
1      10M

notanumber  bad
2      5K
"""
        let result = TopCompressedSource.parse(output)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[1], 10 * 1_048_576)
        XCTAssertEqual(result[2], 5 * 1024)
    }

    func testParseEmptyOutputReturnsEmptyMap() {
        XCTAssertTrue(TopCompressedSource.parse("").isEmpty)
    }

    func testParseNoPIDHeaderReturnsEmptyMap() {
        let output = "Processes: 1 total\nLoad Avg: 0.1\n"
        XCTAssertTrue(TopCompressedSource.parse(output).isEmpty)
    }

    // MARK: - parseSize(_:)

    func testParseSizeBytes() {
        XCTAssertEqual(TopCompressedSource.parseSize("0B"), 0)
        XCTAssertEqual(TopCompressedSource.parseSize("512B"), 512)
    }

    func testParseSizeKilobytes() {
        XCTAssertEqual(TopCompressedSource.parseSize("4816K"), 4816 * 1024)
        XCTAssertEqual(TopCompressedSource.parseSize("1K"), 1024)
    }

    func testParseSizeMegabytes() {
        XCTAssertEqual(TopCompressedSource.parseSize("102M"), 102 * 1_048_576)
    }

    func testParseSizeGigabytes() {
        XCTAssertEqual(TopCompressedSource.parseSize("18G"), 18 * 1_073_741_824)
    }

    func testParseSizeTerabytes() {
        XCTAssertEqual(TopCompressedSource.parseSize("1T"), 1_099_511_627_776)
    }

    func testParseSizeDecimalGigabytes() {
        let expected = UInt64((2.5 * 1_073_741_824).rounded())
        XCTAssertEqual(TopCompressedSource.parseSize("2.5G"), expected)
    }

    func testParseSizeBareDigits() {
        XCTAssertEqual(TopCompressedSource.parseSize("12345"), 12345)
    }

    func testParseSizeInvalidReturnsNil() {
        XCTAssertNil(TopCompressedSource.parseSize(""))
        XCTAssertNil(TopCompressedSource.parseSize("abc"))
        XCTAssertNil(TopCompressedSource.parseSize("XM"))
    }
}
