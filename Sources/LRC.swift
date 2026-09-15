import Foundation

struct LRCLine: Codable, Equatable {
    let time: TimeInterval
    let text: String
}

struct LRCParser {
    private static let timePattern = try! NSRegularExpression(
        pattern: #"\[(\d{1,2}):(\d{2})(?:[\.:](\d{1,3}))?\]"#
    )

    static func parse(_ lrc: String) -> [LRCLine] {
        var lines: [LRCLine] = []
        for rawLine in lrc.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            let matches = timePattern.matches(in: line, range: range)
            guard !matches.isEmpty else { continue }

            let textStart = matches.reduce(0) { max($0, $1.range.location + $1.range.length) }
            let text = String(line[Range(NSRange(location: textStart, length: line.utf16.count - textStart), in: line)!])
                .trimmingCharacters(in: .whitespaces)
            for match in matches {
                guard let minuteRange = Range(match.range(at: 1), in: line),
                      let secondRange = Range(match.range(at: 2), in: line),
                      let minute = Int(line[minuteRange]),
                      let second = Int(line[secondRange]) else { continue }
                var fraction = 0.0
                if match.range(at: 3).location != NSNotFound,
                   let fractionRange = Range(match.range(at: 3), in: line),
                   let value = Int(line[fractionRange]) {
                    let digits = match.range(at: 3).length
                    fraction = Double(value) / pow(10.0, Double(digits))
                }
                lines.append(LRCLine(time: Double(minute * 60 + second) + fraction, text: text))
            }
        }
        return lines.sorted { $0.time == $1.time ? $0.text < $1.text : $0.time < $1.time }
    }

    static func line(at seconds: TimeInterval, from lines: [LRCLine]) -> String? {
        guard !lines.isEmpty else { return nil }
        var low = 0
        var high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if lines[middle].time <= seconds { low = middle + 1 } else { high = middle }
        }
        guard low > 0 else { return nil }
        return lines[low - 1].text.isEmpty ? nil : lines[low - 1].text
    }
}
