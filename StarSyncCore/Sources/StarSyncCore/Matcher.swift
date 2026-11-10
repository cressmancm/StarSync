import Foundation

/// The outcome of looking for a Lightroom photo's counterpart in Apple Photos.
public enum MatchOutcome: Sendable, Equatable {
    /// Exactly one photo in the library is this Lightroom photo.
    case matched(PhotoAsset, confidence: MatchConfidence)
    /// Several candidates survived every test; the person picks.
    case ambiguous([PhotoAsset])
    /// Nothing in Photos corresponds to this photo, which is normal: most
    /// raw files are never exported.
    case notInPhotos
}

public enum MatchConfidence: String, Sendable, Equatable {
    /// One photo had this file name, nothing else to decide.
    case uniqueFilename
    /// Several shared the file name; capture time settled it.
    case filenameAndDate
    /// Several shared name and time; pixel dimensions settled it.
    case filenameAndDimensions
    /// The file name only matched after stripping a `-Edit`-style suffix.
    case derivedFilename
}

public struct Match: Sendable, Identifiable {
    public let asset: LRAsset
    public let outcome: MatchOutcome
    public var id: String { asset.id }

    public var photo: PhotoAsset? {
        if case .matched(let photo, _) = outcome { return photo }
        return nil
    }
}

public struct MatchReport: Sendable {
    public let matches: [Match]
    /// Photos whose file name was unavailable, so they could never be matched.
    public let unidentifiablePhotos: Int

    public var matched: [Match] { matches.filter { $0.photo != nil } }
    public var ambiguous: [Match] {
        matches.filter { if case .ambiguous = $0.outcome { return true } else { return false } }
    }
    public var notInPhotos: [Match] {
        matches.filter { $0.outcome == .notInPhotos }
    }
}

/// Pairs Lightroom photos with their Apple Photos copies.
///
/// Lightroom exports keep the camera's file name, so the file name stem is the
/// primary key; capture time and pixel dimensions break ties when a stem is
/// reused, which happens with virtual copies and across camera bodies that
/// restart their counters.
public struct Matcher: Sendable {
    /// Capture times within this many seconds are the same moment.
    public static let exactDateTolerance: TimeInterval = 2
    /// Widened window that absorbs a time-zone or daylight-saving shift
    /// between what Lightroom recorded and what Photos stored.
    public static let looseDateTolerance: TimeInterval = 3600 + exactDateTolerance

    private let calendar: Calendar
    private let timeZone: TimeZone

    public init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    public func match(assets: [LRAsset], photos: [PhotoAsset]) -> MatchReport {
        var index: [String: [PhotoAsset]] = [:]
        var unidentifiable = 0

        for photo in photos {
            guard let stem = photo.stem, !stem.isEmpty else {
                unidentifiable += 1
                continue
            }
            index[stem, default: []].append(photo)
            // Also index under the base name, so a Lightroom original can find
            // a Photos copy that was exported as "DSCF4087-Edit.jpg".
            if let base = FilenameMatching.strippingDerivedSuffix(stem), index[base] == nil || !index[base]!.contains(where: { $0.id == photo.id }) {
                index[base, default: []].append(photo)
            }
        }

        let matches = assets.map { asset in
            Match(asset: asset, outcome: outcome(for: asset, in: index))
        }
        return MatchReport(matches: matches, unidentifiablePhotos: unidentifiable)
    }

    // MARK: - Resolution

    private func outcome(for asset: LRAsset, in index: [String: [PhotoAsset]]) -> MatchOutcome {
        let stem = asset.stem
        guard !stem.isEmpty else { return .notInPhotos }

        if let candidates = index[stem], !candidates.isEmpty {
            return resolve(asset: asset, candidates: candidates, baseConfidence: .uniqueFilename)
        }
        // Second pass: a Lightroom file that is itself a derived file, e.g.
        // "DSCF3438-Edit.tiff" exported as "DSCF3438.jpg".
        if let base = FilenameMatching.strippingDerivedSuffix(stem),
           let candidates = index[base], !candidates.isEmpty {
            return resolve(asset: asset, candidates: candidates, baseConfidence: .derivedFilename)
        }
        return .notInPhotos
    }

    private func resolve(
        asset: LRAsset,
        candidates: [PhotoAsset],
        baseConfidence: MatchConfidence
    ) -> MatchOutcome {
        let unique = uniqued(candidates)
        if unique.count == 1 {
            return .matched(unique[0], confidence: baseConfidence)
        }

        // Narrow by capture time, tightest window first.
        if let captureDate = parseCaptureDate(asset.captureDate) {
            for tolerance in [Self.exactDateTolerance, Self.looseDateTolerance] {
                let withinWindow = unique.filter { photo in
                    guard let date = photo.creationDate else { return false }
                    return abs(date.timeIntervalSince(captureDate)) <= tolerance
                }
                if withinWindow.count == 1 {
                    return .matched(withinWindow[0], confidence: .filenameAndDate)
                }
                if withinWindow.count > 1 {
                    // Same name, same moment: fall back to pixel dimensions.
                    if let bySize = uniqueBySize(asset: asset, candidates: withinWindow) {
                        return .matched(bySize, confidence: .filenameAndDimensions)
                    }
                    return .ambiguous(withinWindow)
                }
            }
        }

        if let bySize = uniqueBySize(asset: asset, candidates: unique) {
            return .matched(bySize, confidence: .filenameAndDimensions)
        }
        return .ambiguous(unique)
    }

    /// Returns the single candidate whose pixel dimensions match the
    /// Lightroom original, allowing for a 90° rotation. Nil unless exactly one
    /// candidate matches, since a crop or a resize on export breaks this test.
    private func uniqueBySize(asset: LRAsset, candidates: [PhotoAsset]) -> PhotoAsset? {
        guard let width = asset.pixelWidth, let height = asset.pixelHeight else { return nil }
        let fits = candidates.filter { photo in
            guard let pw = photo.pixelWidth, let ph = photo.pixelHeight else { return false }
            return (pw == width && ph == height) || (pw == height && ph == width)
        }
        return fits.count == 1 ? fits[0] : nil
    }

    private func uniqued(_ photos: [PhotoAsset]) -> [PhotoAsset] {
        var seen = Set<String>()
        return photos.filter { seen.insert($0.id).inserted }
    }

    // MARK: - Dates

    /// Lightroom records capture time as local wall-clock with no zone, e.g.
    /// `2024-01-06T17:13:58`. Photos stores an absolute instant. Reading the
    /// Lightroom string in a given zone makes the two comparable; the loose
    /// tolerance covers the case where that zone is not the one the shutter
    /// was pressed in.
    func parseCaptureDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }

        var components = DateComponents()
        components.timeZone = timeZone

        let datePart = raw.prefix(while: { $0 != "T" && $0 != " " })
        let dateFields = datePart.split(separator: "-")
        guard dateFields.count == 3,
              let year = Int(dateFields[0]),
              let month = Int(dateFields[1]),
              let day = Int(dateFields[2])
        else { return nil }
        components.year = year
        components.month = month
        components.day = day

        if let separator = raw.firstIndex(where: { $0 == "T" || $0 == " " }) {
            var timePart = raw[raw.index(after: separator)...]
            // Trailing zone designators, when Lightroom includes one.
            if timePart.hasSuffix("Z") {
                components.timeZone = TimeZone(secondsFromGMT: 0)
                timePart = timePart.dropLast()
            }
            let timeFields = timePart.split(separator: ":")
            if timeFields.count >= 2 {
                components.hour = Int(timeFields[0])
                components.minute = Int(timeFields[1])
                if timeFields.count >= 3 {
                    components.second = Int(Double(timeFields[2]).map { $0.rounded(.down) } ?? 0)
                }
            }
        }
        return calendar.date(from: components)
    }
}

extension MatchReport {
    /// The same report with fresh Photos ratings folded into the matched photos.
    ///
    /// Matching looks at file names, capture times and pixel dimensions and
    /// never at ratings, so a report stays valid when a rating changes
    /// underneath it — only the rating itself needs replacing. That makes it
    /// cheap to re-read the ratings of the few hundred photos a run actually
    /// touches, rather than enumerating the whole library again.
    public func updatingPhotoRatings(_ ratings: [String: Int]) -> MatchReport {
        guard !ratings.isEmpty else { return self }
        let updated = matches.map { match -> Match in
            guard case .matched(let photo, let confidence) = match.outcome,
                  let rating = ratings[photo.id],
                  rating != photo.rating
            else { return match }
            return Match(
                asset: match.asset,
                outcome: .matched(photo.withRating(rating), confidence: confidence)
            )
        }
        return MatchReport(matches: updated, unidentifiablePhotos: unidentifiablePhotos)
    }

    /// The identifiers of every photo this report matched, for re-reading
    /// their ratings before a plan is built.
    public var matchedPhotoIdentifiers: [String] {
        matches.compactMap(\.photo?.id)
    }
}
