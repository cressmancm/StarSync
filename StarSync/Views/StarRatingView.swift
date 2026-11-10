import SwiftUI

/// Five stars, shown filled to `rating`.
struct StarRatingView: View {
    let rating: Int
    var size: CGFloat = 11
    var dimmed = false

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { position in
                Image(systemName: position <= rating ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(position <= rating
                                     ? (dimmed ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
                                     : AnyShapeStyle(.quaternary))
            }
        }
        .accessibilityLabel(rating == 0 ? "Unrated" : "\(rating) star\(rating == 1 ? "" : "s")")
    }
}

/// Five stars the person can set, used to override one row.
struct StarRatingPicker: View {
    @Binding var rating: Int
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { position in
                Button {
                    // Clicking the current rating clears it.
                    rating = (rating == position) ? 0 : position
                } label: {
                    Image(systemName: position <= rating ? "star.fill" : "star")
                        .font(.system(size: size))
                        .foregroundStyle(position <= rating ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                }
                .buttonStyle(.plain)
                .help("\(position) star\(position == 1 ? "" : "s")")
            }
        }
    }
}

/// A short label describing what will happen to one photo.
struct ActionBadge: View {
    let text: String
    let tone: Tone

    enum Tone {
        case write, conflict, neutral, blocked

        var color: Color {
            switch self {
            case .write: return .accentColor
            case .conflict: return .orange
            case .neutral: return .secondary
            case .blocked: return .red
            }
        }
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tone.color.opacity(0.14), in: Capsule())
            .foregroundStyle(tone.color)
    }
}
