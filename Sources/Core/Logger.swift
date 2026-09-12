import Foundation
import os

/// 日志级别。
enum LogLevel: Int, Sendable, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        }
    }

    var tag: String {
        switch self {
        case .debug: return "D"
        case .info: return "I"
        case .warning: return "W"
        case .error: return "E"
        }
    }
}

/// 可选文件日志落盘器。内部用 NSLock 串行化写入,线程安全。
final class FileLogSink: @unchecked Sendable {
    private let lock = NSLock()
    private var handle: FileHandle?

    private(set) var fileURL: URL?

    func enable(at url: URL) {
        lock.lock()
        defer { lock.unlock() }
        handle?.tryClose()
        handle = nil
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            handle = try FileHandle(forWritingTo: url)
            handle?.seekToEndOfFile()
            fileURL = url
        } catch {
            handle = nil
            fileURL = nil
        }
    }

    func disable() {
        lock.lock()
        defer { lock.unlock() }
        handle?.tryClose()
        handle = nil
    }

    var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return handle != nil
    }

    func write(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let handle, let data = line.data(using: .utf8) else { return }
        handle.write(data)
    }
}

/// 单条日志记录(内存环形缓冲,只读展示用)。与文件落盘/系统日志并行,互不影响。
struct LogEntry: Sendable, Identifiable, Equatable {
    let id: UInt64
    let level: LogLevel
    let date: Date
    let file: String
    let line: Int
    let message: String
}

/// 内存环形缓冲:NSLock 串行化,线程安全。供「操作日志」页只读展示。
final class LogBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [LogEntry] = []
    private var nextID: UInt64 = 0
    private let capacity: Int

    init(capacity: Int = 500) {
        self.capacity = max(1, capacity)
    }

    func append(level: LogLevel, date: Date, file: String, line: Int, message: String) {
        lock.lock()
        defer { lock.unlock() }
        let entry = LogEntry(id: nextID, level: level, date: date, file: file, line: line, message: message)
        nextID &+= 1
        storage.append(entry)
        if storage.count > capacity {
            storage.removeFirst(storage.count - capacity)
        }
    }

    func entries() -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }
}

/// 简单日志系统:系统统一日志(os.Logger)+ print(DEBUG 下)+ 可选文件落盘。
enum Log {
    private static let osLogger = os.Logger(
        subsystem: "com.linminhao.DeviceToolbox",
        category: "general"
    )
    private static let fileSink = FileLogSink()
    private static let buffer = LogBuffer()

    // MARK: - 各级别输出

    static func debug(_ message: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
        log(.debug, message(), file, line)
    }

    static func info(_ message: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
        log(.info, message(), file, line)
    }

    static func warning(_ message: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
        log(.warning, message(), file, line)
    }

    static func error(_ message: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
        log(.error, message(), file, line)
    }

    // MARK: - 文件日志开关

    /// 启用文件日志(写入指定 URL)。日志文件通常放在 Cache 目录。
    static func enableFileLogging(at url: URL) {
        fileSink.enable(at: url)
        if fileSink.isEnabled {
            osLogger.info("文件日志已启用: \(url.path, privacy: .public)")
        } else {
            osLogger.error("文件日志启用失败: \(url.path, privacy: .public)")
        }
    }

    static func disableFileLogging() {
        fileSink.disable()
    }

    static func logFileURL() -> URL? {
        fileSink.fileURL
    }

    static func isFileLoggingEnabled() -> Bool {
        fileSink.isEnabled
    }

    // MARK: - 内存环形缓冲读取(只读,供日志查看页)

    /// 返回最近最多 `capacity` 条日志(可选按级别过滤,`error` 之外均可)。按时间正序返回。
    static func entries(levelFilter: LogLevel? = nil) -> [LogEntry] {
        let all = buffer.entries()
        guard let filter = levelFilter else { return all }
        return all.filter { $0.level == filter }
    }

    /// 清空内存缓冲(幂等;不影响系统日志与文件落盘)。
    static func clearBuffer() {
        buffer.removeAll()
    }

    /// 导出为纯文本(整段复制/分享用)。
    static func exportText(levelFilter: LogLevel? = nil) -> String {
        entries(levelFilter: levelFilter)
            .map(LogEntryFormatter.line)
            .joined(separator: "\n")
    }

    // MARK: - 内部

    private static func log(_ level: LogLevel, _ message: String, _ file: String, _ line: Int) {
        let formatted = "[\(level.tag)][\(file):\(line)] \(message)"
        osLogger.log(level: level.osLogType, "\(formatted, privacy: .public)")
        fileSink.write(formatted + "\n")
        buffer.append(level: level, date: Date(), file: file, line: line, message: message)
        #if DEBUG
        print(formatted)
        #endif
    }
}

/// 日志条目纯文本格式化(自由函数,避免在 detached 闭包里捕获 MainActor 隔离的 View)。
enum LogEntryFormatter {
    /// 形如 `HH:mm:ss.SSS [I] file:line message`。
    static func line(_ entry: LogEntry) -> String {
        let time = entry.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
        return "\(time) [\(entry.level.tag)] \(entry.file):\(entry.line) \(entry.message)"
    }
}

private extension FileHandle {
    func tryClose() {
        try? close()
    }
}
