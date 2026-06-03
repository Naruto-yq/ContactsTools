import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    var body: some View {
        TabView {
            SpreadsheetToVCardView()
                .tabItem { Label(AppText.localized("表格转VCF", "Sheet to VCF"), systemImage: "tablecells") }

            VCFToExcelView()
                .tabItem { Label(AppText.localized("VCF转Excel", "VCF to Excel"), systemImage: "doc.richtext") }

            ContactsExportView()
                .tabItem { Label(AppText.localized("通讯录导出", "Contacts Export"), systemImage: "person.crop.circle") }
        }
    }
}

private struct SpreadsheetToVCardView: View {
    @StateObject private var viewModel = ContactToolViewModel()
    @State private var isImporterPresented = false
    @State private var sharePayload: SharePayload?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    importCard
                    if viewModel.table != nil {
                        mappingCard
                        statsGrid
                        ContactPreviewCard(title: AppText.localized("预览", "Preview"), subtitle: AppText.localizedFormat("前 %d 条", "First %d", viewModel.previewContacts.count), contacts: viewModel.previewContacts, allContacts: viewModel.contacts)
                        if !viewModel.issues.isEmpty { issuesCard }
                        exportCard
                    }
                    guideCard
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(AppText.localized("表格转 VCF", "Sheet to VCF"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(AppText.localized("模板", "Template")) { TemplateView() }
                }
            }
            .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.commaSeparatedText, .plainText, .xlsx], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { viewModel.importFile(url: url) }
                case .failure(let error):
                    viewModel.errorMessage = error.localizedDescription
                }
            }
            .sheet(item: $sharePayload) { payload in
                ShareSheet(items: payload.items)
            }
            .toolAlert(message: $viewModel.errorMessage)
        }
    }

    private var importCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(AppText.localized("导入数据", "Import Data")).font(.headline)
                    Spacer()
                    if !viewModel.fileType.isEmpty {
                        Text(viewModel.fileType).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }

                if let table = viewModel.table {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text").font(.title2).foregroundStyle(.teal)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.fileName).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(AppText.localizedFormat("表头第 %d 行 · %d 行数据", "Header row %d · %d data rows", table.headerRowNumber, table.rows.count)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(AppText.localized("清空", "Clear")) { viewModel.clear() }.buttonStyle(.borderless)
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppText.localized("选择 .xlsx 或 .csv 文件", "Choose a .xlsx or .csv file")).font(.title3.weight(.semibold))
                        Text(AppText.localized("首行使用：姓名、手机号、邮箱、公司、地址、备注", "Use the first row as: Name, Phone, Email, Company, Address, Note")).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                }

                HStack(spacing: 12) {
                    Button { isImporterPresented = true } label: {
                        Label(AppText.localized("选择文件", "Choose File"), systemImage: "folder").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)

                    NavigationLink { TemplateView() } label: {
                        Label(AppText.localized("查看模板", "View Template"), systemImage: "tablecells").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.teal)
                }

                Text(AppText.localized("请从系统“文件”App、iCloud Drive 或本机文件位置选择 CSV 或 Excel 文件。", "Choose CSV or Excel files from the system Files app, iCloud Drive, or local file locations."))
                    .font(.footnote)
                    .foregroundStyle(.blue)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var mappingCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppText.localized("字段映射", "Field Mapping")).font(.headline)
                if let table = viewModel.table {
                    ForEach(ContactField.allCases) { field in
                        Picker(selection: Binding(get: { viewModel.mapping[field] ?? -1 }, set: { viewModel.updateMapping(field: field, column: $0) })) {
                            Text(AppText.localized("不导入", "Do Not Import")).tag(-1)
                            ForEach(table.headers.indices, id: \.self) { index in
                                Text(AppText.localizedFormat("%@列 · %@", "%@ · %@", FieldDetector.columnLabel(for: index), table.headers[index])).tag(index)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(field.title)
                                if field.isRequired { Text(AppText.localized("必填", "Required")).font(.caption2.weight(.bold)).foregroundStyle(.red) }
                            }
                        }
                    }

                    Picker(AppText.localized("国家码", "Country Code"), selection: Binding(get: { viewModel.selectedCountryCode }, set: { viewModel.updateCountryCode($0) })) {
                        ForEach(CountryCode.options) { option in Text(option.label).tag(option) }
                    }
                }
            }
        }
    }

    private var statsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            StatCard(value: "\(viewModel.stats.validCount)", label: AppText.localized("可生成", "Ready"))
            StatCard(value: "\(viewModel.stats.skippedCount)", label: AppText.localized("已跳过", "Skipped"))
            StatCard(value: "\(viewModel.stats.duplicateCount)", label: AppText.localized("重复", "Duplicates"))
            StatCard(value: viewModel.vcfSizeLabel, label: AppText.localized("大小", "Size"))
        }
    }

    private var issuesCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(AppText.localized("异常行", "Issues")).font(.headline)
                    Spacer()
                    Text(AppText.localized("最多显示 80 条", "Showing up to 80")).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(viewModel.issues) { issue in
                    HStack(alignment: .top, spacing: 10) {
                        Text(AppText.localizedFormat("第 %d 行", "Row %d", issue.rowNumber)).font(.caption.weight(.semibold)).frame(width: 72, alignment: .leading)
                        Text(issue.message).font(.caption).foregroundStyle(issue.level == .error ? .red : .orange)
                        Spacer()
                    }
                }
            }
        }
    }

    private var exportCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(AppText.localized("生成文件", "Export File")).font(.headline)
                    Spacer()
                    Text("contacts.vcf").font(.caption).foregroundStyle(.secondary)
                }
                Text(AppText.localized("生成后会打开 iOS 系统分享面板，可保存到文件 App 或发送给其他应用。", "After generation, the iOS share sheet will open so you can save to Files or send to another app."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ExportFileNameField(placeholder: "contacts", text: $viewModel.exportFileName)
                Button {
                    do {
                        let url = try viewModel.makeVCardFile()
                        sharePayload = SharePayload(items: [url])
                    } catch {
                        viewModel.errorMessage = error.localizedDescription
                    }
                } label: {
                    Label(AppText.localized("生成并系统分享 VCF", "Generate and Share VCF"), systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
            }
        }
    }

    private var guideCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppText.localized("iPhone 导入教程", "iPhone Import Guide")).font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppText.localized("1. 生成 contacts.vcf 后，使用系统分享面板保存到“文件”App。", "1. After generating contacts.vcf, use the share sheet to save it to the Files app."))
                    Text(AppText.localized("2. 在“文件”App 中打开 vcf 文件，选择用“通讯录”打开。", "2. Open the vcf file in Files, then choose to open it with Contacts."))
                    Text(AppText.localized("3. 确认添加全部联系人。", "3. Confirm adding all contacts."))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct VCFToExcelView: View {
    @StateObject private var viewModel = VCFToExcelViewModel()
    @State private var isImporterPresented = false
    @State private var sharePayload: SharePayload?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    importCard
                    if !viewModel.contacts.isEmpty {
                        StatCard(value: "\(viewModel.contacts.count)", label: AppText.localized("已解析联系人", "Parsed Contacts"))
                        ContactPreviewCard(title: AppText.localized("预览", "Preview"), subtitle: AppText.localizedFormat("前 %d 条", "First %d", viewModel.previewContacts.count), contacts: viewModel.previewContacts, allContacts: viewModel.contacts)
                        exportCard
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(AppText.localized("VCF 转 Excel", "VCF to Excel"))
            .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.vcf], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { viewModel.importFile(url: url) }
                case .failure(let error):
                    viewModel.errorMessage = error.localizedDescription
                }
            }
            .sheet(item: $sharePayload) { payload in ShareSheet(items: payload.items) }
            .toolAlert(message: $viewModel.errorMessage)
        }
    }

    private var importCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(AppText.localized("导入 VCF", "Import VCF")).font(.headline)
                    Spacer()
                    if !viewModel.fileName.isEmpty { Text("VCF").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.fileName.isEmpty ? AppText.localized("选择 .vcf 文件", "Choose a .vcf file") : viewModel.fileName)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Text(AppText.localized("解析通讯录文件后，可导出 Excel 或 CSV。", "After parsing the contacts file, you can export Excel or CSV."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))

                Button { isImporterPresented = true } label: {
                    Label(AppText.localized("选择 VCF 文件", "Choose VCF File"), systemImage: "doc.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
            }
        }
    }

    private var exportCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppText.localized("生成文件", "Export File")).font(.headline)
                Text(AppText.localized("生成后会打开 iOS 系统分享面板，可保存到文件 App 或发送给其他应用。", "After generation, the iOS share sheet will open so you can save to Files or send to another app."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ExportFileNameField(placeholder: "contacts_from_vcf", text: $viewModel.exportFileName)
                HStack(spacing: 12) {
                    Button {
                        do { sharePayload = SharePayload(items: [try viewModel.makeExcelFile()]) }
                        catch { viewModel.errorMessage = error.localizedDescription }
                    } label: {
                        Label(AppText.localized("系统分享 Excel", "Share Excel"), systemImage: "tablecells").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)

                    Button {
                        do { sharePayload = SharePayload(items: [try viewModel.makeCSVFile()]) }
                        catch { viewModel.errorMessage = error.localizedDescription }
                    } label: {
                        Label(AppText.localized("系统分享 CSV", "Share CSV"), systemImage: "doc.plaintext").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.teal)
                }
            }
        }
    }
}

private struct ContactsExportView: View {
    @StateObject private var viewModel = ContactsExportViewModel()
    @State private var sharePayload: SharePayload?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    permissionCard
                    if !viewModel.contacts.isEmpty {
                        selectionToolbar
                        contactsList
                        exportCard
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(AppText.localized("通讯录导出", "Contacts Export"))
            .sheet(item: $sharePayload) { payload in ShareSheet(items: payload.items) }
            .toolAlert(message: $viewModel.errorMessage)
            .task { viewModel.loadIfAuthorized() }
        }
    }

    private var permissionCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(AppText.localized("系统通讯录", "System Contacts")).font(.headline)
                    Spacer()
                    Text(viewModel.permissionLabel).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text(AppText.localized("选择手机通讯录联系人后，可以导出为 VCF、Excel 或 CSV。首次读取需要授权访问系统通讯录。", "Select contacts from your device and export them as VCF, Excel, or CSV. Accessing system contacts requires permission the first time."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button { viewModel.requestAndLoadContacts() } label: {
                    Label(viewModel.contacts.isEmpty ? AppText.localized("读取通讯录", "Load Contacts") : AppText.localized("重新读取", "Reload"), systemImage: "person.crop.circle.badge.checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
            }
        }
    }

    private var selectionToolbar: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(AppText.localizedFormat("已选择 %d / %d", "Selected %d / %d", viewModel.selectedCount, viewModel.contacts.count))
                        .font(.headline)
                    Spacer()
                }
                HStack(spacing: 12) {
                    Button(AppText.localized("全选", "Select All")) { viewModel.selectAll() }
                        .buttonStyle(.bordered)
                        .tint(.teal)
                        .frame(maxWidth: .infinity)
                    Button(AppText.localized("清空", "Clear")) { viewModel.clearSelection() }
                        .buttonStyle(.bordered)
                        .tint(.teal)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var contactsList: some View {
        CardView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.contacts) { item in
                    Button { viewModel.toggleSelection(item.id) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: viewModel.isSelected(item.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(viewModel.isSelected(item.id) ? .teal : .secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.record.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                FlowText(values: [item.record.phone, item.record.company, item.record.email].filter { !$0.isEmpty })
                            }
                            Spacer()
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    if item.id != viewModel.contacts.last?.id { Divider() }
                }
            }
        }
    }

    private var exportCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppText.localized("生成文件", "Export File")).font(.headline)
                Text(AppText.localized("生成后会打开 iOS 系统分享面板，可保存到文件 App 或发送给其他应用。", "After generation, the iOS share sheet will open so you can save to Files or send to another app."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ExportFileNameField(placeholder: "phone_contacts", text: $viewModel.exportFileName)
                HStack(spacing: 10) {
                    exportButton(title: "VCF", icon: "person.text.rectangle", action: viewModel.makeVCardFile)
                    exportButton(title: "Excel", icon: "tablecells", action: viewModel.makeExcelFile)
                    exportButton(title: "CSV", icon: "doc.plaintext", action: viewModel.makeCSVFile)
                }
            }
        }
    }

    @ViewBuilder
    private func exportButton(title: String, icon: String, action: @escaping () throws -> URL) -> some View {
        let button = Button {
            do { sharePayload = SharePayload(items: [try action()]) }
            catch { viewModel.errorMessage = error.localizedDescription }
        } label: {
            Label(title, systemImage: icon).frame(maxWidth: .infinity)
        }

        if title == "VCF" {
            button.buttonStyle(.borderedProminent).tint(.teal)
        } else {
            button.buttonStyle(.bordered).tint(.teal)
        }
    }
}

private struct CardView<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator).opacity(0.25), lineWidth: 1))
    }
}

private struct ContactPreviewCard: View {
    let title: String
    let subtitle: String
    let contacts: [ContactRecord]
    let allContacts: [ContactRecord]

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text(title).font(.headline)
                    Spacer()
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    if allContacts.count > contacts.count {
                        NavigationLink { AllContactsView(contacts: allContacts) } label: {
                            HStack(spacing: 2) {
                                Text(AppText.localized("全部", "All"))
                                Image(systemName: "chevron.right")
                            }
                            .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderless)
                        .tint(.teal)
                    }
                }

                if contacts.isEmpty {
                    Text(AppText.localized("暂无联系人", "No contacts yet")).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 8)
                } else {
                    ForEach(contacts) { contact in
                        ContactSummaryRow(contact: contact)
                        if contact.id != contacts.last?.id { Divider() }
                    }
                }
            }
        }
    }
}

private struct AllContactsView: View {
    let contacts: [ContactRecord]

    var body: some View {
        List(contacts) { contact in
            ContactDetailRow(contact: contact)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        }
        .navigationTitle(AppText.localized("全部联系人", "All Contacts"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ContactSummaryRow: View {
    let contact: ContactRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(contact.name).font(.subheadline.weight(.semibold))
                Spacer()
                if !contact.phone.isEmpty {
                    Text(contact.phone).font(.subheadline.weight(.semibold)).foregroundStyle(.teal)
                }
            }
            FlowText(values: [contact.company, contact.email, contact.address].filter { !$0.isEmpty })
        }
    }
}

private struct ContactDetailRow: View {
    let contact: ContactRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(contact.name)
                    .font(.headline)
                Spacer()
                Text(AppText.localizedFormat("第 %d 条", "No. %d", contact.rowNumber))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ContactInfoLine(title: AppText.localized("手机号", "Phone"), value: contact.phone, icon: "phone")
            ContactInfoLine(title: AppText.localized("邮箱", "Email"), value: contact.email, icon: "envelope")
            ContactInfoLine(title: AppText.localized("公司", "Company"), value: contact.company, icon: "building.2")
            ContactInfoLine(title: AppText.localized("地址", "Address"), value: contact.address, icon: "mappin.and.ellipse")
            ContactInfoLine(title: AppText.localized("备注", "Note"), value: contact.note, icon: "note.text")
        }
    }
}

private struct ContactInfoLine: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        if !value.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.teal)
                    .frame(width: 18, alignment: .center)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct ExportFileNameField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppText.localized("导出文件名", "Export File Name"))
                .font(.subheadline.weight(.semibold))
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Text(AppText.localized("无需输入扩展名，导出时会按文件格式自动补齐。", "No need to enter an extension. It will be added automatically for the selected format."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct StatCard: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator).opacity(0.25), lineWidth: 1))
    }
}

private struct FlowText: View {
    let values: [String]

    var body: some View {
        if !values.isEmpty {
            Text(values.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
    }
}

private extension View {
    func toolAlert(message: Binding<String?>) -> some View {
        alert(AppText.localized("提示", "Notice"), isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })) {
            Button(AppText.localized("知道了", "OK"), role: .cancel) { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

private extension UTType {
    static var xlsx: UTType { UTType(filenameExtension: "xlsx") ?? .data }
    static var vcf: UTType { UTType(filenameExtension: "vcf") ?? .data }
}
