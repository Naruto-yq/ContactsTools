import Foundation

enum ContactCleaner {
    static func clean(rows: [TableRow], mapping: [ContactField: Int], countryCode: String) -> CleanResult {
        var contacts: [ContactRecord] = []
        var issues: [DataIssue] = []
        var seenPhones = Set<String>()
        var duplicateCount = 0
        var skippedCount = 0
        var warningCount = 0

        for row in rows {
            let rawPhone = cell(row, field: .phone, mapping: mapping)
            let phone = normalizePhone(rawPhone, countryCode: countryCode)

            guard !phone.isEmpty else {
                skippedCount += 1
                issues.append(DataIssue(level: .error, rowNumber: row.rowNumber, message: AppText.localized("空手机号，已跳过", "Empty phone number. Skipped.")))
                continue
            }

            guard isPhoneReasonable(phone) else {
                skippedCount += 1
                issues.append(DataIssue(level: .error, rowNumber: row.rowNumber, message: AppText.localized("手机号长度异常，已跳过", "Phone number length is invalid. Skipped.")))
                continue
            }

            let dedupeKey = phone.filter(\.isNumber)
            guard !seenPhones.contains(dedupeKey) else {
                duplicateCount += 1
                skippedCount += 1
                issues.append(DataIssue(level: .warning, rowNumber: row.rowNumber, message: AppText.localized("手机号重复，已保留首次出现", "Duplicate phone number. Kept the first occurrence.")))
                continue
            }
            seenPhones.insert(dedupeKey)

            var email = cell(row, field: .email, mapping: mapping).replacingOccurrences(of: " ", with: "")
            if !email.isEmpty && !isValidEmail(email) {
                warningCount += 1
                issues.append(DataIssue(level: .warning, rowNumber: row.rowNumber, message: AppText.localized("邮箱格式异常，生成时将忽略邮箱", "Invalid email format. Email will be ignored when exporting.")))
                email = ""
            }

            let name = cell(row, field: .name, mapping: mapping)
            contacts.append(ContactRecord(
                rowNumber: row.rowNumber,
                name: name.isEmpty ? phone : name,
                phone: phone,
                email: email,
                company: cell(row, field: .company, mapping: mapping),
                address: cell(row, field: .address, mapping: mapping),
                note: cell(row, field: .note, mapping: mapping)
            ))
        }

        return CleanResult(
            contacts: contacts,
            issues: issues,
            stats: CleanStats(totalRows: rows.count, validCount: contacts.count, skippedCount: skippedCount, duplicateCount: duplicateCount, warningCount: warningCount)
        )
    }

    static func normalizePhone(_ raw: String, countryCode: String) -> String {
        var phone = raw.trimmed
        guard !phone.isEmpty else { return "" }

        if phone.hasSuffix(".0") {
            phone.removeLast(2)
        }
        if phone.hasPrefix("00") {
            phone = "+" + phone.dropFirst(2)
        }

        phone = phone.replacingOccurrences(of: "－", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "（", with: "")
            .replacingOccurrences(of: "）", with: "")

        phone = String(phone.filter { $0.isNumber || $0 == "+" })
        if let firstPlus = phone.firstIndex(of: "+") {
            let prefix = phone[..<phone.index(after: firstPlus)]
            let suffix = phone[phone.index(after: firstPlus)...].filter { $0 != "+" }
            phone = String(prefix) + String(suffix)
        }

        if !countryCode.isEmpty, !phone.hasPrefix("+") {
            let digits = countryCode.replacingOccurrences(of: "+", with: "")
            phone = phone.hasPrefix(digits) ? "+" + phone : countryCode + phone.drop { $0 == "0" }
        }

        return phone
    }

    private static func cell(_ row: TableRow, field: ContactField, mapping: [ContactField: Int]) -> String {
        guard let index = mapping[field], index >= 0, row.values.indices.contains(index) else { return "" }
        return row.values[index].trimmed
    }

    private static func isPhoneReasonable(_ phone: String) -> Bool {
        let digits = phone.filter(\.isNumber)
        return digits.count >= 6 && digits.count <= 20
    }

    private static func isValidEmail(_ email: String) -> Bool {
        email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }
}
