import Foundation

enum VCardBuilder {
    static func build(contacts: [ContactRecord]) -> String {
        contacts.map { contact in
            var lines = [
                "BEGIN:VCARD",
                "VERSION:3.0",
                "FN:\(escape(contact.name))",
                "TEL;TYPE=CELL:\(escape(contact.phone))"
            ]

            if !contact.email.isEmpty { lines.append("EMAIL:\(escape(contact.email))") }
            if !contact.company.isEmpty { lines.append("ORG:\(escape(contact.company))") }
            if !contact.address.isEmpty { lines.append("ADR;TYPE=HOME:;;\(escape(contact.address));;;;") }
            if !contact.note.isEmpty { lines.append("NOTE:\(escape(contact.note))") }

            lines.append("END:VCARD")
            return lines.joined(separator: "\r\n")
        }.joined(separator: "\r\n") + "\r\n"
    }

    static func writeTemporaryFile(contacts: [ContactRecord], fileName: String = "contacts.vcf") throws -> URL {
        let text = build(contacts: contacts)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func formattedSize(contacts: [ContactRecord]) -> String {
        let count = build(contacts: contacts).data(using: .utf8)?.count ?? 0
        if count < 1024 { return "\(count) B" }
        if count < 1024 * 1024 { return String(format: "%.1f KB", Double(count) / 1024.0) }
        return String(format: "%.2f MB", Double(count) / 1024.0 / 1024.0)
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
    }
}

enum VCFParser {
    static func parse(data: Data) throws -> [ContactRecord] {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode) else {
            throw ContactToolError.parseFailure(AppText.localized("VCF 编码无法识别。", "VCF encoding could not be detected."))
        }
        return parse(text: text)
    }

    static func parse(text: String) -> [ContactRecord] {
        let lines = unfoldLines(text)
        var records: [ContactRecord] = []
        var values: [String: String] = [:]
        var rowNumber = 1

        for line in lines {
            let upper = line.uppercased()
            if upper == "BEGIN:VCARD" {
                values = [:]
                continue
            }
            if upper == "END:VCARD" {
                if let record = makeRecord(values: values, rowNumber: rowNumber) {
                    records.append(record)
                    rowNumber += 1
                }
                values = [:]
                continue
            }

            guard let colon = line.firstIndex(of: ":") else { continue }
            let keyPart = String(line[..<colon])
            let rawValue = String(line[line.index(after: colon)...])
            let key = keyPart.split(separator: ";", maxSplits: 1).first.map { String($0).uppercased() } ?? ""

            switch key {
            case "FN", "TEL", "EMAIL", "ORG", "NOTE":
                if values[key]?.isEmpty != false {
                    values[key] = unescape(rawValue)
                }
            case "ADR":
                if values[key]?.isEmpty != false {
                    let parts = splitEscaped(rawValue, separator: ";").map(unescape)
                    let useful = parts.dropFirst(2).filter { !$0.trimmed.isEmpty }
                    values[key] = useful.joined(separator: " ").trimmed
                }
            case "N":
                if values["FN"]?.isEmpty != false {
                    let parts = splitEscaped(rawValue, separator: ";").map(unescape)
                    values["N"] = parts.filter { !$0.trimmed.isEmpty }.joined(separator: " ").trimmed
                }
            default:
                continue
            }
        }

        return records
    }

    private static func makeRecord(values: [String: String], rowNumber: Int) -> ContactRecord? {
        let phone = (values["TEL"] ?? "").trimmed
        let name = (values["FN"] ?? values["N"] ?? phone).trimmed
        guard !name.isEmpty || !phone.isEmpty else { return nil }
        return ContactRecord(
            rowNumber: rowNumber,
            name: name.isEmpty ? phone : name,
            phone: phone,
            email: (values["EMAIL"] ?? "").trimmed,
            company: (values["ORG"] ?? "").trimmed,
            address: (values["ADR"] ?? "").trimmed,
            note: (values["NOTE"] ?? "").trimmed
        )
    }

    private static func unfoldLines(_ text: String) -> [String] {
        let rawLines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var lines: [String] = []

        for line in rawLines {
            if line.hasPrefix(" ") || line.hasPrefix("\t"), !lines.isEmpty {
                lines[lines.count - 1] += String(line.dropFirst())
            } else {
                lines.append(line)
            }
        }
        return lines
    }

    private static func splitEscaped(_ value: String, separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var isEscaped = false
        for char in value {
            if isEscaped {
                current.append(char)
                isEscaped = false
            } else if char == "\\" {
                current.append(char)
                isEscaped = true
            } else if char == separator {
                parts.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        parts.append(current)
        return parts
    }

    private static func unescape(_ value: String) -> String {
        var result = ""
        var isEscaped = false
        for char in value {
            if isEscaped {
                switch char {
                case "n", "N": result.append("\n")
                case ",", ";", "\\": result.append(char)
                default: result.append(char)
                }
                isEscaped = false
            } else if char == "\\" {
                isEscaped = true
            } else {
                result.append(char)
            }
        }
        return result
    }
}
