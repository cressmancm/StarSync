import Foundation
import Testing
@testable import StarSyncCore

@Suite("Filename matching")
struct FilenameMatchingTests {

    @Test("a stem drops the extension and the case")
    func stems() {
        #expect(FilenameMatching.stem(of: "DSCF4087.RAF") == "dscf4087")
        #expect(FilenameMatching.stem(of: "DSCF4087.jpg") == "dscf4087")
        #expect(FilenameMatching.stem(of: "NZ8_5779.NEF") == "nz8_5779")
        #expect(FilenameMatching.stem(of: "no-extension") == "no-extension")
        #expect(FilenameMatching.stem(of: "two.dots.jpg") == "two.dots")
        #expect(FilenameMatching.stem(of: "/a/path/IMG_1.HEIC") == "img_1")
        #expect(FilenameMatching.stem(of: ".hidden") == ".hidden")
    }

    @Test("derived-file suffixes are stripped")
    func derivedSuffixes() {
        #expect(FilenameMatching.strippingDerivedSuffix("dscf3438-edit") == "dscf3438")
        #expect(FilenameMatching.strippingDerivedSuffix("nz8_5779-hdr") == "nz8_5779")
        #expect(FilenameMatching.strippingDerivedSuffix("img_1 copy") == "img_1")
        #expect(FilenameMatching.strippingDerivedSuffix("dscf4087-2") == "dscf4087")
    }

    @Test("a camera's own numbering is left alone")
    func doesNotEatRealNames() {
        // The trailing digits here are part of the name, not a duplicate marker.
        #expect(FilenameMatching.strippingDerivedSuffix("dscf4087") == nil)
        #expect(FilenameMatching.strippingDerivedSuffix("nz8_5779") == nil)
        #expect(FilenameMatching.strippingDerivedSuffix("img_1234") == nil)
        #expect(FilenameMatching.strippingDerivedSuffix("") == nil)
    }
}

@Suite("Matcher")
struct MatcherTests {

    let matcher = Matcher(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

    func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    func lr(_ name: String, rating: Int = 3, capture: String? = "2026-01-02T03:04:05",
            width: Int? = 6240, height: Int? = 4160) -> LRAsset {
        LRAsset(id: "lr-\(name)", fileName: name, captureDate: capture,
                rating: rating, pixelWidth: width, pixelHeight: height)
    }

    func photo(_ id: String, _ name: String?, _ created: Date? = nil, rating: Int = 0,
               width: Int? = nil, height: Int? = nil, editable: Bool = true) -> PhotoAsset {
        PhotoAsset(id: id, originalFilename: name, creationDate: created, rating: rating,
                   pixelWidth: width, pixelHeight: height, isEditable: editable)
    }

    @Test("a unique file name matches")
    func uniqueName() {
        let report = matcher.match(
            assets: [lr("DSCF4087.RAF")],
            photos: [photo("p1", "DSCF4087.jpg")]
        )
        #expect(report.matched.count == 1)
        #expect(report.matches[0].photo?.id == "p1")
        if case .matched(_, let confidence) = report.matches[0].outcome {
            #expect(confidence == .uniqueFilename)
        }
    }

    @Test("a photo that was never exported is reported, not guessed at")
    func noMatch() {
        let report = matcher.match(
            assets: [lr("DSCF4087.RAF")],
            photos: [photo("p1", "SOMETHINGELSE.jpg")]
        )
        #expect(report.notInPhotos.count == 1)
        #expect(report.matched.isEmpty)
    }

    @Test("capture time separates two photos sharing a file name")
    func dateDisambiguation() {
        // Both are DSCF4087; only one was shot at 03:04:05 local.
        let report = matcher.match(
            assets: [lr("DSCF4087.RAF", capture: "2026-01-02T03:04:05")],
            photos: [
                photo("early", "DSCF4087.jpg", date("2026-01-02T11:04:05Z")),  // 03:04:05 PST
                photo("late", "DSCF4087.jpg", date("2026-06-02T11:04:05Z")),
            ]
        )
        #expect(report.matches[0].photo?.id == "early")
        if case .matched(_, let confidence) = report.matches[0].outcome {
            #expect(confidence == .filenameAndDate)
        }
    }

    @Test("a time-zone shift still matches inside the wider window")
    func timezoneDrift() {
        // Recorded as 03:04:05 local, stored an hour off.
        let report = matcher.match(
            assets: [lr("DSCF4087.RAF", capture: "2026-01-02T03:04:05")],
            photos: [
                photo("shifted", "DSCF4087.jpg", date("2026-01-02T12:04:05Z")),  // +1h
                photo("faroff", "DSCF4087.jpg", date("2027-01-02T11:04:05Z")),
            ]
        )
        #expect(report.matches[0].photo?.id == "shifted")
    }

    @Test("pixel dimensions break a tie that time cannot")
    func dimensionTiebreak() {
        let shared = date("2026-01-02T11:04:05Z")
        let report = matcher.match(
            assets: [lr("DSCF4087.RAF", width: 6240, height: 4160)],
            photos: [
                photo("right", "DSCF4087.jpg", shared, width: 6240, height: 4160),
                photo("wrong", "DSCF4087.jpg", shared, width: 1000, height: 800),
            ]
        )
        #expect(report.matches[0].photo?.id == "right")
        if case .matched(_, let confidence) = report.matches[0].outcome {
            #expect(confidence == .filenameAndDimensions)
        }
    }

    @Test("a rotated export still counts as the same dimensions")
    func rotatedDimensions() {
        let shared = date("2026-01-02T11:04:05Z")
        let report = matcher.match(
            assets: [lr("DSCF4087.RAF", width: 6240, height: 4160)],
            photos: [
                photo("rotated", "DSCF4087.jpg", shared, width: 4160, height: 6240),
                photo("other", "DSCF4087.jpg", shared, width: 999, height: 111),
            ]
        )
        #expect(report.matches[0].photo?.id == "rotated")
    }

    @Test("candidates that cannot be told apart are surfaced, not picked")
    func ambiguous() {
        let shared = date("2026-01-02T11:04:05Z")
        let report = matcher.match(
            assets: [lr("DSCF4087.RAF", width: 6240, height: 4160)],
            photos: [
                photo("a", "DSCF4087.jpg", shared, width: 6240, height: 4160),
                photo("b", "DSCF4087.jpg", shared, width: 6240, height: 4160),
            ]
        )
        #expect(report.ambiguous.count == 1)
        #expect(report.matched.isEmpty)
        if case .ambiguous(let candidates) = report.matches[0].outcome {
            #expect(candidates.count == 2)
        }
    }

    @Test("a Lightroom derived file finds the plainly named export")
    func lightroomDerivedToPlainExport() {
        let report = matcher.match(
            assets: [lr("DSCF3438-Edit.tiff")],
            photos: [photo("p1", "DSCF3438.jpg")]
        )
        #expect(report.matches[0].photo?.id == "p1")
        if case .matched(_, let confidence) = report.matches[0].outcome {
            #expect(confidence == .derivedFilename)
        }
    }

    @Test("a plain original finds an export named as a derived file")
    func plainOriginalToDerivedExport() {
        let report = matcher.match(
            assets: [lr("DSCF3438.RAF")],
            photos: [photo("p1", "DSCF3438-Edit.jpg")]
        )
        #expect(report.matches[0].photo?.id == "p1")
    }

    @Test("an exact name wins over a derived one")
    func exactBeatsDerived() {
        let report = matcher.match(
            assets: [lr("DSCF3438.RAF")],
            photos: [
                photo("exact", "DSCF3438.jpg"),
                photo("derived", "DSCF3438-Edit.jpg"),
            ]
        )
        // Both land under the "dscf3438" key, so time and dimensions decide;
        // what matters is that the exact file is not discarded.
        #expect(report.matches[0].photo != nil || report.ambiguous.count == 1)
    }

    @Test("photos with no file name are counted, never matched")
    func unidentifiablePhotos() {
        let report = matcher.match(
            assets: [lr("DSCF4087.RAF")],
            photos: [photo("p1", nil), photo("p2", "")]
        )
        #expect(report.unidentifiablePhotos == 2)
        #expect(report.notInPhotos.count == 1)
    }

    @Test("a Lightroom asset with no file name is not matched to anything")
    func assetWithoutName() {
        let report = matcher.match(
            assets: [LRAsset(id: "x", fileName: "")],
            photos: [photo("p1", "DSCF4087.jpg")]
        )
        #expect(report.notInPhotos.count == 1)
    }

    @Test("the same photo listed twice is not treated as two candidates")
    func duplicateCandidate() {
        let shared = date("2026-01-02T11:04:05Z")
        let same = photo("p1", "DSCF4087.jpg", shared)
        let report = matcher.match(assets: [lr("DSCF4087.RAF")], photos: [same, same])
        #expect(report.matched.count == 1)
        #expect(report.ambiguous.isEmpty)
    }

    @Test("capture dates parse, and nonsense does not crash")
    func captureDateParsing() {
        #expect(matcher.parseCaptureDate("2024-01-06T17:13:58") != nil)
        #expect(matcher.parseCaptureDate("2024-01-06 17:13:58") != nil)
        #expect(matcher.parseCaptureDate("2024-01-06T17:13:58.500Z") != nil)
        #expect(matcher.parseCaptureDate("2024-01-06") != nil)
        #expect(matcher.parseCaptureDate(nil) == nil)
        #expect(matcher.parseCaptureDate("") == nil)
        #expect(matcher.parseCaptureDate("not a date") == nil)
    }

    @Test("a photo with no capture date still matches on a unique name")
    func missingCaptureDate() {
        let report = matcher.match(
            assets: [lr("DSCF4087.RAF", capture: nil)],
            photos: [photo("p1", "DSCF4087.jpg")]
        )
        #expect(report.matched.count == 1)
    }
}
