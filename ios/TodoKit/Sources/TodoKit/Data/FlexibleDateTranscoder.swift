import Foundation
import OpenAPIRuntime

/// Decodes RFC 3339 `date-time` values with or without fractional seconds. The mock sends
/// `2026-10-20T14:00:00Z`; a Spring backend may well send `2026-10-20T14:00:00.123456Z`.
struct FlexibleDateTranscoder: DateTranscoder {
    func encode(_ date: Date) throws -> String {
        date.formatted(.iso8601)
    }

    func decode(_ dateString: String) throws -> Date {
        if let date = try? Date.ISO8601FormatStyle().parse(dateString) { return date }
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(dateString) { return date }
        throw DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "Expected date string to be ISO8601-formatted, got \(dateString)")
        )
    }
}
