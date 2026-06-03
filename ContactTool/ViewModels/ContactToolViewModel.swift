import Contacts
import Foundation

@MainActor
final class ContactToolViewModel: ObservableObject {
    @Published var fileName = ""
    @Published var fileType = ""
    @Published var table: ParsedTable?
    @Published var mapping: [ContactField: Int] = Dictionary(uniqueKeysWithValues: ContactField.allCases.map { ($0, -1) })
    @Published var selectedCountryCode = CountryCode.options[1]
    @Published var contacts: [ContactRecord] = []
    @Published var issues: [DataIssue] = []
    @Published var stats = CleanStats()
    @Published var errorMessage: String?
    @Published var exportFileName = "contacts"

    var previewContacts: [ContactRecord] { Array(contacts.prefix(5)) }
    var vcfSizeLabel: String { contacts.isEmpty ? "0 B" : VCardBuilder.formattedSize(contacts: contacts) }

    func importFile(url: URL) {
        do {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            let ext = url.pathExtension.lowercased()
            let rawRows: [[String]]
            switch ext {
            case "csv": rawRows = try CSVParser.parse(data: data)
            case "xlsx": rawRows = try XLSXParser.parse(data: data)
            default: throw ContactToolError.unsupportedFile
            }

            let parsed = try FieldDetector.buildTable(from: rawRows)
            table = parsed
            mapping = FieldDetector.detectMapping(headers: parsed.headers)
            fileName = url.lastPathComponent
            fileType = ext.uppercased()
            rebuildPreview()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateMapping(field: ContactField, column: Int) {
        mapping[field] = column
        rebuildPreview()
    }

    func updateCountryCode(_ countryCode: CountryCode) {
        selectedCountryCode = countryCode
        rebuildPreview()
    }

    func clear() {
        fileName = ""
        fileType = ""
        table = nil
        mapping = Dictionary(uniqueKeysWithValues: ContactField.allCases.map { ($0, -1) })
        contacts = []
        issues = []
        stats = CleanStats()
        exportFileName = "contacts"
    }

    func makeVCardFile() throws -> URL {
        guard !contacts.isEmpty else { throw ContactToolError.noValidContacts }
        return try VCardBuilder.writeTemporaryFile(contacts: contacts, fileName: ExportFileName.make(from: exportFileName, defaultBaseName: "contacts", fileExtension: "vcf"))
    }

    private func rebuildPreview() {
        guard let table else {
            contacts = []
            issues = []
            stats = CleanStats()
            return
        }

        let result = ContactCleaner.clean(rows: table.rows, mapping: mapping, countryCode: selectedCountryCode.value)
        contacts = result.contacts
        issues = Array(result.issues.prefix(80))
        stats = result.stats
    }
}

@MainActor
final class VCFToExcelViewModel: ObservableObject {
    @Published var fileName = ""
    @Published var contacts: [ContactRecord] = []
    @Published var errorMessage: String?
    @Published var exportFileName = "contacts_from_vcf"

    var previewContacts: [ContactRecord] { Array(contacts.prefix(5)) }

    func importFile(url: URL) {
        do {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

            guard url.pathExtension.lowercased() == "vcf" else {
                throw ContactToolError.unsupportedVCFFile
            }

            contacts = try VCFParser.parse(data: Data(contentsOf: url))
            fileName = url.lastPathComponent
            if contacts.isEmpty { throw ContactToolError.noValidContacts }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func makeExcelFile() throws -> URL {
        guard !contacts.isEmpty else { throw ContactToolError.noValidContacts }
        return try SpreadsheetExporter.writeXLSX(contacts: contacts, fileName: ExportFileName.make(from: exportFileName, defaultBaseName: "contacts_from_vcf", fileExtension: "xlsx"))
    }

    func makeCSVFile() throws -> URL {
        guard !contacts.isEmpty else { throw ContactToolError.noValidContacts }
        return try SpreadsheetExporter.writeCSV(contacts: contacts, fileName: ExportFileName.make(from: exportFileName, defaultBaseName: "contacts_from_vcf", fileExtension: "csv"))
    }
}

struct PhoneContactItem: Identifiable, Hashable {
    let id: String
    let record: ContactRecord
}

@MainActor
final class ContactsExportViewModel: ObservableObject {
    @Published var contacts: [PhoneContactItem] = []
    @Published var selectedIDs = Set<String>()
    @Published var errorMessage: String?
    @Published var permissionLabel = AppText.localized("未授权", "Not Authorized")
    @Published var exportFileName = "phone_contacts"

    private let store = CNContactStore()

    var selectedCount: Int { selectedIDs.count }
    private var selectedRecords: [ContactRecord] {
        contacts.filter { selectedIDs.contains($0.id) }.map(\.record)
    }

    func loadIfAuthorized() {
        if isAuthorized(CNContactStore.authorizationStatus(for: .contacts)) {
            loadContacts()
        } else {
            updatePermissionLabel()
        }
    }

    func requestAndLoadContacts() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if isAuthorized(status) {
            loadContacts()
            return
        }

        guard status == .notDetermined else {
            updatePermissionLabel()
            errorMessage = AppText.localized("请在系统设置中允许“联系人工具箱”访问通讯录。", "Please allow Contact Toolbox to access Contacts in Settings.")
            return
        }

        store.requestAccess(for: .contacts) { [weak self] granted, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.errorMessage = error.localizedDescription
                    self.updatePermissionLabel()
                    return
                }
                if granted {
                    self.loadContacts()
                } else {
                    self.updatePermissionLabel()
                    self.errorMessage = AppText.localized("未获得通讯录权限，无法读取联系人。", "Contacts permission was not granted, so contacts cannot be read.")
                }
            }
        }
    }

    func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func isSelected(_ id: String) -> Bool {
        selectedIDs.contains(id)
    }

    func selectAll() {
        selectedIDs = Set(contacts.map(\.id))
    }

    func clearSelection() {
        selectedIDs.removeAll()
    }

    func makeVCardFile() throws -> URL {
        let records = selectedRecords
        guard !records.isEmpty else { throw ContactToolError.noContactsSelected }
        return try VCardBuilder.writeTemporaryFile(contacts: records, fileName: ExportFileName.make(from: exportFileName, defaultBaseName: "phone_contacts", fileExtension: "vcf"))
    }

    func makeExcelFile() throws -> URL {
        let records = selectedRecords
        guard !records.isEmpty else { throw ContactToolError.noContactsSelected }
        return try SpreadsheetExporter.writeXLSX(contacts: records, fileName: ExportFileName.make(from: exportFileName, defaultBaseName: "phone_contacts", fileExtension: "xlsx"))
    }

    func makeCSVFile() throws -> URL {
        let records = selectedRecords
        guard !records.isEmpty else { throw ContactToolError.noContactsSelected }
        return try SpreadsheetExporter.writeCSV(contacts: records, fileName: ExportFileName.make(from: exportFileName, defaultBaseName: "phone_contacts", fileExtension: "csv"))
    }

    private func loadContacts() {
        do {
            updatePermissionLabel()
            contacts = try fetchContacts()
            selectedIDs = Set(contacts.map(\.id))
            if contacts.isEmpty {
                errorMessage = AppText.localized("通讯录中没有可导出的联系人。", "There are no contacts available to export.")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchContacts() throws -> [PhoneContactItem] {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactMiddleNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .userDefault
        var items: [PhoneContactItem] = []
        let formatter = CNContactFormatter()
        let addressFormatter = CNPostalAddressFormatter()

        try store.enumerateContacts(with: request) { contact, _ in
            let phones = contact.phoneNumbers.map { $0.value.stringValue }.filter { !$0.trimmed.isEmpty }
            let primaryPhone = phones.first ?? ""
            let name = formatter.string(from: contact)?.trimmed
                ?? [contact.familyName, contact.givenName, contact.middleName].joined().trimmed
            let email = contact.emailAddresses.first.map { String($0.value) } ?? ""
            let address = contact.postalAddresses.first.map { labeledValue in
                addressFormatter.string(from: labeledValue.value)
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmed
            } ?? ""
            let displayName = name.isEmpty ? (contact.organizationName.trimmed.isEmpty ? primaryPhone : contact.organizationName.trimmed) : name

            guard !displayName.isEmpty || !primaryPhone.isEmpty || !email.isEmpty else { return }

            let record = ContactRecord(
                rowNumber: items.count + 1,
                name: displayName.isEmpty ? primaryPhone : displayName,
                phone: primaryPhone,
                email: email,
                company: contact.organizationName.trimmed,
                address: address,
                note: ""
            )
            items.append(PhoneContactItem(id: contact.identifier, record: record))
        }

        return items
    }

    private func updatePermissionLabel() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .notDetermined:
            permissionLabel = AppText.localized("未申请", "Not Requested")
        case .restricted:
            permissionLabel = AppText.localized("受限制", "Restricted")
        case .denied:
            permissionLabel = AppText.localized("已拒绝", "Denied")
        case .authorized:
            permissionLabel = AppText.localized("已授权", "Authorized")
        case .limited:
            permissionLabel = AppText.localized("部分授权", "Limited")
        @unknown default:
            permissionLabel = AppText.localized("未知", "Unknown")
        }
    }

    private func isAuthorized(_ status: CNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined, .restricted, .denied:
            return false
        @unknown default:
            return false
        }
    }
}

enum ContactToolError: LocalizedError {
    case unsupportedFile
    case unsupportedVCFFile
    case parseFailure(String)
    case noValidContacts
    case noContactsSelected

    var errorDescription: String? {
        switch self {
        case .unsupportedFile: return AppText.localized("仅支持 CSV 或 XLSX 文件。", "Only CSV or XLSX files are supported.")
        case .unsupportedVCFFile: return AppText.localized("仅支持 VCF 文件。", "Only VCF files are supported.")
        case .parseFailure(let message): return message
        case .noValidContacts: return AppText.localized("没有可生成的联系人。", "There are no contacts to export.")
        case .noContactsSelected: return AppText.localized("请先选择至少一个联系人。", "Please select at least one contact first.")
        }
    }
}


enum ExportFileName {
    static func make(from rawValue: String, defaultBaseName: String, fileExtension: String) -> String {
        let normalizedExtension = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        var baseName = rawValue.trimmed
        if baseName.lowercased().hasSuffix(".\(normalizedExtension)") {
            baseName.removeLast(normalizedExtension.count + 1)
        }

        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        baseName = baseName
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmed

        if baseName.isEmpty { baseName = defaultBaseName }
        if baseName.count > 120 { baseName = String(baseName.prefix(120)).trimmed }
        return "\(baseName).\(normalizedExtension)"
    }
}
