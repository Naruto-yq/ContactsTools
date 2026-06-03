import Foundation

struct CountryCode: Identifiable, Hashable {
    let label: String
    let value: String

    var id: String { value.isEmpty ? "none" : value }

    static var options: [CountryCode] {
        [
            CountryCode(label: AppText.localized("不添加", "None"), value: ""),
            CountryCode(label: AppText.localized("+86 中国大陆", "+86 Mainland China"), value: "+86"),
            CountryCode(label: AppText.localized("+65 新加坡", "+65 Singapore"), value: "+65"),
            CountryCode(label: AppText.localized("+1 美国/加拿大", "+1 US/Canada"), value: "+1")
        ]
    }
}

enum ContactField: String, CaseIterable, Identifiable, Hashable {
    case name
    case phone
    case email
    case company
    case address
    case note

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return AppText.localized("姓名", "Name")
        case .phone: return AppText.localized("手机号", "Phone")
        case .email: return AppText.localized("邮箱", "Email")
        case .company: return AppText.localized("公司", "Company")
        case .address: return AppText.localized("地址", "Address")
        case .note: return AppText.localized("备注", "Note")
        }
    }

    var isRequired: Bool { self == .phone }
}

struct TableRow: Identifiable, Hashable {
    let rowNumber: Int
    let values: [String]

    var id: Int { rowNumber }
}

struct ParsedTable: Hashable {
    let headerRowNumber: Int
    let headers: [String]
    let rows: [TableRow]
}

struct ContactRecord: Identifiable, Hashable {
    let rowNumber: Int
    let name: String
    let phone: String
    let email: String
    let company: String
    let address: String
    let note: String

    var id: String { "\(rowNumber)-\(phone)" }
}

struct DataIssue: Identifiable, Hashable {
    enum Level: String {
        case error
        case warning
    }

    let level: Level
    let rowNumber: Int
    let message: String

    var id: String { "\(rowNumber)-\(level.rawValue)-\(message)" }
}

struct CleanStats: Hashable {
    var totalRows: Int = 0
    var validCount: Int = 0
    var skippedCount: Int = 0
    var duplicateCount: Int = 0
    var warningCount: Int = 0
}

struct CleanResult: Hashable {
    let contacts: [ContactRecord]
    let issues: [DataIssue]
    let stats: CleanStats
}


enum AppText {
    static var isChinese: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    static func localized(_ zh: String, _ en: String) -> String {
        isChinese ? zh : en
    }

    static func localizedFormat(_ zh: String, _ en: String, _ arguments: CVarArg...) -> String {
        String(format: localized(zh, en), locale: Locale(identifier: isChinese ? "zh_CN" : "en_US"), arguments: arguments)
    }
}
