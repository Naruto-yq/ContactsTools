import Foundation

enum FieldDetector {
    private static let aliases: [ContactField: [String]] = [
        .name: ["姓名", "名字", "联系人", "客户姓名", "学生姓名", "家长姓名", "称呼", "name", "fullname", "contact"],
        .phone: ["手机号", "手机号码", "手机", "电话", "联系电话", "号码", "mobile", "phone", "tel", "telephone"],
        .email: ["邮箱", "电子邮箱", "邮件", "email", "mail", "e-mail"],
        .company: ["公司", "单位", "机构", "学校", "企业", "组织", "company", "org", "organization"],
        .address: ["地址", "住址", "联系地址", "通讯地址", "收货地址", "家庭地址", "办公地址", "address", "addr", "location"],
        .note: ["备注", "说明", "标签", "来源", "note", "notes", "remark", "comment"]
    ]

    static func buildTable(from rawRows: [[String]]) throws -> ParsedTable {
        guard !rawRows.isEmpty else {
            throw ContactToolError.parseFailure(AppText.localized("文件中没有可读取的数据。", "No readable data was found in the file."))
        }

        let headerIndex = findHeaderIndex(in: rawRows)
        let width = rawRows.map(\.count).max() ?? 0
        let headerRow = rawRows[safe: headerIndex] ?? []
        let headers = (0..<width).map { index -> String in
            let header = (headerRow[safe: index] ?? "").trimmed
            return header.isEmpty ? AppText.localizedFormat("第%d列", "Column %d", index + 1) : header
        }

        let rows = rawRows.dropFirst(headerIndex + 1).enumerated().compactMap { offset, row -> TableRow? in
            let values = (0..<width).map { index in (row[safe: index] ?? "").trimmed }
            guard values.contains(where: { !$0.isEmpty }) else { return nil }
            return TableRow(rowNumber: headerIndex + offset + 2, values: values)
        }

        return ParsedTable(headerRowNumber: headerIndex + 1, headers: headers, rows: rows)
    }

    static func detectMapping(headers: [String]) -> [ContactField: Int] {
        var usedColumns = Set<Int>()
        var mapping: [ContactField: Int] = [:]

        for field in ContactField.allCases {
            var bestIndex = -1
            var bestScore = 0

            for (index, header) in headers.enumerated() where !usedColumns.contains(index) {
                let score = fieldScore(field, header: header)
                if score > bestScore {
                    bestScore = score
                    bestIndex = index
                }
            }

            mapping[field] = bestScore >= 60 ? bestIndex : -1
            if bestIndex >= 0 { usedColumns.insert(bestIndex) }
        }

        return mapping
    }

    static func columnLabel(for index: Int) -> String {
        var number = index + 1
        var label = ""
        while number > 0 {
            let remainder = (number - 1) % 26
            label = String(UnicodeScalar(65 + remainder)!) + label
            number = (number - 1) / 26
        }
        return label
    }

    private static func findHeaderIndex(in rawRows: [[String]]) -> Int {
        let firstNonBlank = rawRows.firstIndex { row in
            row.contains { !$0.trimmed.isEmpty }
        } ?? 0
        let limit = min(rawRows.count, 20)
        var bestIndex = firstNonBlank
        var bestScore = -1

        for index in 0..<limit {
            let score = rowScore(rawRows[index])
            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }

        return bestScore > 0 ? bestIndex : firstNonBlank
    }

    private static func rowScore(_ row: [String]) -> Int {
        ContactField.allCases.reduce(0) { total, field in
            let best = row.map { fieldScore(field, header: $0) }.max() ?? 0
            return total + (best >= 60 ? 1 : 0)
        }
    }

    private static func fieldScore(_ field: ContactField, header: String) -> Int {
        let normalized = normalize(header)
        guard !normalized.isEmpty else { return 0 }
        var best = 0

        for alias in aliases[field] ?? [] {
            let target = normalize(alias)
            if normalized == target {
                best = max(best, 100)
            } else if normalized.contains(target) {
                best = max(best, 80)
            } else if target.contains(normalized), normalized.count >= 2 {
                best = max(best, 60)
            }
        }

        return best
    }

    private static func normalize(_ text: String) -> String {
        let removed = CharacterSet(charactersIn: " _-—–:：/\\|()[]（）【】")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .unicodeScalars
            .filter { !removed.contains($0) }
            .map(String.init)
            .joined()
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
