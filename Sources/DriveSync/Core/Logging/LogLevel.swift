import Foundation

enum LogLevel: String, Comparable, CaseIterable, Sendable {
    case debug = "DEBUG"
    case info  = "INFO"
    case warn  = "WARN"
    case error = "ERROR"

    private var order: Int {
        switch self {
        case .debug: return 0
        case .info:  return 1
        case .warn:  return 2
        case .error: return 3
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.order < rhs.order
    }

    /// Padded string for aligned log output (5 chars)
    var padded: String {
        switch self {
        case .debug: return "DEBUG"
        case .info:  return "INFO "
        case .warn:  return "WARN "
        case .error: return "ERROR"
        }
    }

    /// SF Symbol icon name for UI
    var icon: String {
        switch self {
        case .debug: return "ant"
        case .info:  return "info.circle"
        case .warn:  return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        }
    }
}
