import Foundation
import AppKit

struct LogEntry: Identifiable, Sendable {
    let id   = UUID()
    let time : String    // "HH:mm:ss"
    let level: LogLevel
    let message: String
}

actor LogManager {
    static let shared = LogManager()

    static let logDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/drivesync/logs")

    // MARK: - Internal State

    private var buffer: [String] = []
    private var fileHandle: FileHandle?
    private var currentDateStr: String = ""
    private var ringBuffer: [LogEntry] = []
    private var continuations: [UUID: AsyncStream<LogEntry>.Continuation] = [:]
    private var flushTask: Task<Void, Never>?

    private static let bufferFlushSize = 20
    private static let ringBufferSize = 100
    private static let flushInterval: TimeInterval = 5

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    func log(_ level: LogLevel, _ message: String) {
        let minLevel = currentMinLevel()
        guard level >= minLevel else { return }

        let now = Date()
        let timeStr = timeFormatter.string(from: now)
        let dateStr = dateFormatter.string(from: now)

        let entry = LogEntry(time: timeStr, level: level, message: message)
        let line = "[\(timeStr)] [\(level.padded)] \(message)"

        // Ring buffer for stream replay
        ringBuffer.append(entry)
        if ringBuffer.count > Self.ringBufferSize {
            ringBuffer.removeFirst(ringBuffer.count - Self.ringBufferSize)
        }

        // Broadcast to active streams
        for (_, continuation) in continuations {
            continuation.yield(entry)
        }

        // Handle date rollover
        if dateStr != currentDateStr {
            flushBuffer()
            closeFileHandle()
            currentDateStr = dateStr
            openFileHandle()
            if !buffer.isEmpty || fileHandle != nil {
                // First entry of new day marker (only if not the very first log)
            }
        }

        // Buffer for disk write
        buffer.append(line)
        if buffer.count >= Self.bufferFlushSize {
            flushBuffer()
        }

        // Schedule periodic flush
        if flushTask == nil {
            flushTask = Task {
                try? await Task.sleep(for: .seconds(Self.flushInterval))
                self.flushBuffer()
                self.flushTask = nil
            }
        }
    }

    func debug(_ message: String) { log(.debug, message) }
    func info(_ message: String)  { log(.info, message) }
    func warn(_ message: String)  { log(.warn, message) }
    func error(_ message: String) { log(.error, message) }

    func makeStream() -> AsyncStream<LogEntry> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<LogEntry>.makeStream()

        // Replay ring buffer
        for entry in ringBuffer {
            continuation.yield(entry)
        }

        continuations[id] = continuation
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { await self?.removeContinuation(id: id) }
        }

        return stream
    }

    func deleteOldLogs(keepDays: Int) async {
        let fm = FileManager.default
        let logDir = Self.logDirectory

        guard let files = try? fm.contentsOfDirectory(at: logDir, includingPropertiesForKeys: nil) else { return }

        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -keepDays, to: Date()) else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var deletedCount = 0
        for file in files {
            let name = file.lastPathComponent
            // Match pattern: drivesync-YYYY-MM-DD.log
            guard name.hasPrefix("drivesync-"), name.hasSuffix(".log"),
                  name.count == "drivesync-YYYY-MM-DD.log".count else { continue }

            let dateStr = String(name.dropFirst("drivesync-".count).dropLast(".log".count))
            guard let fileDate = dateFormatter.date(from: dateStr) else { continue }

            if fileDate < cutoffDate {
                try? fm.removeItem(at: file)
                deletedCount += 1
            }
        }

        if deletedCount > 0 {
            info("Log cleanup: deleted \(deletedCount) file(s) older than \(keepDays) days")
        }
    }

    func openTodayLogFile() {
        let url = Self.todayLogFileURL()
        let fm = FileManager.default

        // Ensure directory exists
        try? fm.createDirectory(at: Self.logDirectory, withIntermediateDirectories: true)

        // Create file if not exists
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }

        NSWorkspace.shared.open(url)
    }

    /// Flush synchronously — call before app exit
    func flush() {
        flushBuffer()
        closeFileHandle()
    }

    static func todayLogFileURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())
        return logDirectory.appendingPathComponent("drivesync-\(dateStr).log")
    }

    // MARK: - Private

    private var minLevel: LogLevel = .info

    /// Call from MainActor when log level changes
    func setMinLevel(_ level: LogLevel) {
        minLevel = level
    }

    func syncMinLevelFromConfig() async {
        let raw = await MainActor.run {
            ConfigManager.shared.string(section: "app", key: "log_level")
        }
        minLevel = LogLevel(rawValue: (raw ?? "info").uppercased()) ?? .info
    }

    private func currentMinLevel() -> LogLevel {
        minLevel
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func openFileHandle() {
        let fm = FileManager.default
        let dir = Self.logDirectory
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let fileURL = dir.appendingPathComponent("drivesync-\(currentDateStr).log")
        if !fm.fileExists(atPath: fileURL.path) {
            fm.createFile(atPath: fileURL.path, contents: nil)
        }

        fileHandle = FileHandle(forWritingAtPath: fileURL.path)
        fileHandle?.seekToEndOfFile()
    }

    private func closeFileHandle() {
        try? fileHandle?.close()
        fileHandle = nil
    }

    private func flushBuffer() {
        guard !buffer.isEmpty else { return }

        if fileHandle == nil && !currentDateStr.isEmpty {
            openFileHandle()
        } else if currentDateStr.isEmpty {
            currentDateStr = dateFormatter.string(from: Date())
            openFileHandle()
        }

        let content = buffer.map { $0 + "\n" }.joined()
        if let data = content.data(using: .utf8) {
            do {
                try fileHandle?.write(contentsOf: data)
            } catch {
                fputs("LogManager: failed to write log: \(error)\n", stderr)
            }
        }

        buffer.removeAll(keepingCapacity: true)
        flushTask?.cancel()
        flushTask = nil
    }
}
