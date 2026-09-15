import Foundation
import Darwin

private let netEaseBundleID = "com.netease.163music"
private let ioQueue = DispatchQueue(label: "touchbarlyrics.io")

private struct Playback {
    let title: String
    let artist: String
    let elapsed: TimeInterval
    let duration: TimeInterval
    let rate: Double
    let bundleID: String

    var isPlaying: Bool { rate > 0.01 }
    var key: String { "\(title)\u{001f}\(artist)" }
}

private final class Agent {
    private let root: URL
    private let displayURL: URL
    private let stateURL: URL
    private let cacheURL: URL
    private let nowPlayingCLI: String
    private var lyricLines: [LRCLine] = []
    private var lyricKey = ""
    private var cachedLyrics: [String: [LRCLine]] = [:]

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = support.appendingPathComponent("TouchBarLyrics-MTMR-2", isDirectory: true)
        displayURL = root.appendingPathComponent("display.txt")
        stateURL = root.appendingPathComponent("state.json")
        cacheURL = root.appendingPathComponent("lyrics-cache.json")
        let sibling = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("nowplaying-cli").path
        nowPlayingCLI = ProcessInfo.processInfo.environment["NOWPLAYING_CLI"]
            ?? (FileManager.default.isExecutableFile(atPath: sibling) ? sibling : "/opt/homebrew/bin/nowplaying-cli")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: cacheURL),
           let decoded = try? JSONDecoder().decode([String: [LRCLine]].self, from: data) {
            cachedLyrics = decoded
        }
    }

    func run() {
        tick()
        dispatchMain()
    }

    private func tick() {
        update(readPlayback())
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.tick() }
    }

    private func readPlayback() -> Playback? {
        guard let object = runCLI(["get-raw"]),
              let title = (object["kMRMediaRemoteNowPlayingInfoTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return nil }
        return Playback(
            title: title,
            artist: (object["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            elapsed: number(object["kMRMediaRemoteNowPlayingInfoElapsedTime"]),
            duration: number(object["kMRMediaRemoteNowPlayingInfoDuration"]),
            rate: number(object["kMRMediaRemoteNowPlayingInfoPlaybackRate"]),
            bundleID: object["kMRMediaRemoteNowPlayingInfoClientBundleIdentifier"] as? String ?? ""
        )
    }

    private func number(_ value: Any?) -> Double {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) ?? 0 }
        return 0
    }

    private func update(_ playback: Playback?) {
        guard let playback, playback.bundleID == netEaseBundleID else {
            write(display: "")
            return
        }
        if playback.key != lyricKey {
            lyricKey = playback.key
            lyricLines = cachedLyrics[lyricKey] ?? []
            fetchLyrics(for: playback)
        }
        let line = LRCParser.line(at: playback.elapsed, from: lyricLines) ?? playback.title
        let title = playback.artist.isEmpty ? playback.title : "\(playback.title) - \(playback.artist)"
        write(display: "\(line)\n\(title)")
        writeState(playback: playback, line: line)
    }

    private func fetchLyrics(for playback: Playback) {
        let key = playback.key
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self,
                  let id = self.searchSong(title: playback.title, artist: playback.artist),
                  let json = self.request("https://music.163.com/api/song/lyric?id=\(id)&lv=1&kv=1&tv=-1"),
                  let lyric = ((json["lrc"] as? [String: Any])?["lyric"] as? String) else { return }
            let lines = LRCParser.parse(lyric)
            ioQueue.sync {
                self.cachedLyrics[key] = lines
                self.lyricLines = lines
                try? JSONEncoder().encode(self.cachedLyrics).write(to: self.cacheURL, options: .atomic)
            }
        }
    }

    private func searchSong(title: String, artist: String) -> Int? {
        let query = artist.isEmpty ? title : "\(title) \(artist)"
        guard var components = URLComponents(string: "https://music.163.com/api/search/get/web") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "limit", value: "5"),
            URLQueryItem(name: "s", value: query)
        ]
        guard let url = components.url,
              let json = request(url.absoluteString),
              let songs = ((json["result"] as? [String: Any])?["songs"] as? [[String: Any]]) else { return nil }
        guard let first = songs.first else { return nil }
        let songID = number(first["id"])
        return songID > 0 ? Int(songID) : nil
    }

    private func request(_ address: String) -> [String: Any]? {
        guard let url = URL(string: address) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 TouchBarLyrics/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        let semaphore = DispatchSemaphore(value: 0)
        var result: [String: Any]?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { semaphore.signal() }
            guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            result = object
        }.resume()
        _ = semaphore.wait(timeout: .now() + 8)
        return result
    }

    private func runCLI(_ arguments: [String]) -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: nowPlayingCLI)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func write(display: String) {
        ioQueue.async { [displayURL] in try? display.data(using: .utf8)?.write(to: displayURL, options: .atomic) }
    }

    private func writeState(playback: Playback, line: String) {
        let state: [String: Any] = [
            "title": playback.title,
            "artist": playback.artist,
            "elapsed": playback.elapsed,
            "duration": playback.duration,
            "playing": playback.isPlaying,
            "line": line
        ]
        guard JSONSerialization.isValidJSONObject(state), let data = try? JSONSerialization.data(withJSONObject: state) else { return }
        ioQueue.async { [stateURL] in try? data.write(to: stateURL, options: .atomic) }
    }
}

private func helperPath() -> String {
    let sibling = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("nowplaying-cli").path
    return ProcessInfo.processInfo.environment["NOWPLAYING_CLI"]
        ?? (FileManager.default.isExecutableFile(atPath: sibling) ? sibling : "/opt/homebrew/bin/nowplaying-cli")
}

private func command(_ name: String) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: helperPath())
    process.arguments = [name == "toggle" ? "togglePlayPause" : name]
    do { try process.run(); process.waitUntilExit(); return process.terminationStatus } catch { return 1 }
}

@main
struct TouchBarLyricsMain {
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.count > 1, arguments[1] == "--command", arguments.count > 2 {
            exit(command(arguments[2]))
        } else if arguments.count > 1, arguments[1] == "--display" {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let url = support.appendingPathComponent("TouchBarLyrics-MTMR-2/display.txt")
            if let display = try? String(contentsOf: url, encoding: .utf8) { print(display, terminator: "") }
        } else {
            Agent().run()
        }
    }
}
