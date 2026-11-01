import Foundation

/// One timed line of synced lyrics.
struct LyricLine: Equatable, Sendable {
    let time: TimeInterval
    let text: String
}

/// What the lyrics lookup found for a track.
enum Lyrics: Equatable, Sendable {
    case synced([LyricLine])
    case plain([String])
    case instrumental
}

/// Pure parsing of LRC text ("[01:23.45] line") and line lookup by playback position.
enum LyricsParser {
    private static let secondsPerMinute: TimeInterval = 60

    /// Lines sorted by time. A line may carry several time tags; metadata tags ("[ar:Artist]") are skipped.
    static func parse(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        for rawLine in lrc.split(whereSeparator: \.isNewline) {
            var rest = Substring(rawLine)
            var times: [TimeInterval] = []
            while rest.first == "[", let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let time = time(from: tag) {
                    times.append(time)
                }
                rest = rest[rest.index(after: close)...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            lines += times.map { LyricLine(time: $0, text: text) }
        }
        return lines.sorted { $0.time < $1.time }
    }

    /// "mm:ss", "mm:ss.xx" or "mm:ss:xx"; `nil` for metadata tags.
    static func time(from tag: Substring) -> TimeInterval? {
        let parts = tag.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let minutes = Double(parts[0]) else { return nil }
        let seconds = Double(parts[1].replacingOccurrences(of: ":", with: "."))
        guard let seconds, minutes >= 0, seconds >= 0 else { return nil }
        return minutes * secondsPerMinute + seconds
    }

    /// Index of the line sung at `position`: the last one that has started. `nil` before the first line.
    static func index(at position: TimeInterval, in lines: [LyricLine]) -> Int? {
        var low = 0
        var high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].time <= position {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low == 0 ? nil : low - 1
    }

    /// YouTube video titles carry noise like "Artist - Song (Official Video)"; strips it for a search.
    static func cleanedTitle(_ title: String) -> String {
        let noise = #"\s*[\(\[][^\)\]]*(official|video|audio|lyric|lyrics|visualizer|mv|hd|4k|remaster)[^\)\]]*[\)\]]"#
        return title
            .replacingOccurrences(of: noise, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
    }
}
