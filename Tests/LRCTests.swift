import Foundation

@main
struct LRCTests {
    static func main() {
        let sample = "[ti:Demo]\n[00:01.20]first\n[00:02.500][00:03]second"
        let lines = LRCParser.parse(sample)
        precondition(lines == [
            LRCLine(time: 1.2, text: "first"),
            LRCLine(time: 2.5, text: "second"),
            LRCLine(time: 3.0, text: "second")
        ])
        precondition(LRCParser.line(at: 0.9, from: lines) == nil)
        precondition(LRCParser.line(at: 2.7, from: lines) == "second")
        print("LRC tests passed")
    }
}
