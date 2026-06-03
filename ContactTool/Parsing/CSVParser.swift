import CoreFoundation
import Foundation

enum CSVParser {
    static func parse(data: Data) throws -> [[String]] {
        guard let text = decode(data: data) else {
            throw ContactToolError.parseFailure(AppText.localized("CSV 编码无法识别，请优先使用 UTF-8 或 UTF-8 BOM 格式。", "CSV encoding could not be detected. Please use UTF-8 or UTF-8 BOM."))
        }
        return parse(text: text)
    }

    static func parse(text: String) -> [[String]] {
        let source = text.dropFirst(text.first == "\u{feff}" ? 1 : 0)
        var rows: [[String]] = []
        var row: [String] = []
        var value = ""
        var inQuotes = false
        var index = source.startIndex

        while index < source.endIndex {
            let char = source[index]
            let nextIndex = source.index(after: index)
            let next = nextIndex < source.endIndex ? source[nextIndex] : nil

            if inQuotes {
                if char == "\"" && next == "\"" {
                    value.append("\"")
                    index = source.index(after: nextIndex)
                    continue
                } else if char == "\"" {
                    inQuotes = false
                } else {
                    value.append(char)
                }
                index = nextIndex
                continue
            }

            if char == "\"" {
                inQuotes = true
            } else if char == "," {
                row.append(value.trimmingCharacters(in: .whitespacesAndNewlines))
                value = ""
            } else if char == "\n" || char == "\r" {
                row.append(value.trimmingCharacters(in: .whitespacesAndNewlines))
                appendIfNotBlank(row, to: &rows)
                row = []
                value = ""
                if char == "\r" && next == "\n" {
                    index = source.index(after: nextIndex)
                    continue
                }
            } else {
                value.append(char)
            }

            index = nextIndex
        }

        row.append(value.trimmingCharacters(in: .whitespacesAndNewlines))
        appendIfNotBlank(row, to: &rows)
        return rows
    }

    private static func decode(data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }

        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        return String(data: data, encoding: gb18030)
    }

    private static func appendIfNotBlank(_ row: [String], to rows: inout [[String]]) {
        if row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            rows.append(row)
        }
    }
}
