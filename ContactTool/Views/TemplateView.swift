import SwiftUI
import UIKit

struct TemplateView: View {
    @State private var sharePayload: SharePayload?
    @State private var toastMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                templateTable
                fieldNotes
                actionButtons
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(AppText.localized("联系人模板", "Contact Template"))
        .sheet(item: $sharePayload) { payload in ShareSheet(items: payload.items) }
        .alert(AppText.localized("提示", "Notice"), isPresented: Binding(get: { toastMessage != nil }, set: { if !$0 { toastMessage = nil } })) {
            Button(AppText.localized("知道了", "OK"), role: .cancel) { toastMessage = nil }
        } message: {
            Text(toastMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppText.localized("CSV / Excel 首行模板", "CSV / Excel Header Template")).font(.subheadline.weight(.semibold)).foregroundStyle(.teal)
            Text(AppText.localized("联系人导入模板", "Contact Import Template")).font(.largeTitle.weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var templateTable: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(AppText.localized("模板字段", "Template Fields")).font(.headline)
                Spacer()
                Text(AppText.localizedFormat("%d 列", "%d columns", TemplateProvider.headers.count)).font(.caption).foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    rowView(TemplateProvider.headers, isHeader: true)
                    ForEach(Array(TemplateProvider.rows.enumerated()), id: \.offset) { _, row in
                        rowView(row, isHeader: false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator).opacity(0.35), lineWidth: 1))
            }
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private var fieldNotes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppText.localized("字段说明", "Field Notes")).font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                Text(AppText.localized("手机号为必填列，用于生成联系人和去重。", "Phone is required and is used to create contacts and remove duplicates."))
                Text(AppText.localized("姓名为空时，会自动使用手机号作为联系人姓名。", "If Name is empty, Phone will be used as the contact name."))
                Text(AppText.localized("地址列支持“地址”“住址”“联系地址”等表头。", "Address supports headers such as Address, Home Address, and Mailing Address."))
                Text(AppText.localized("备注会写入通讯录备注字段。", "Note will be written to the contact notes field."))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                UIPasteboard.general.string = TemplateProvider.csv(includeBOM: false)
                toastMessage = AppText.localized("模板内容已复制。", "Template content copied.")
            } label: {
                Label(AppText.localized("复制内容", "Copy"), systemImage: "doc.on.doc").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.teal)

            Button {
                do {
                    let url = try TemplateProvider.writeTemporaryCSV()
                    sharePayload = SharePayload(items: [url])
                } catch {
                    toastMessage = error.localizedDescription
                }
            } label: {
                Label(AppText.localized("系统分享 CSV 模板", "Share CSV Template"), systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
        }
    }

    private func rowView(_ values: [String], isHeader: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Text(value)
                    .font(isHeader ? .caption.weight(.bold) : .caption)
                    .foregroundStyle(isHeader ? .primary : .secondary)
                    .frame(width: 150, alignment: .leading)
                    .frame(minHeight: 46)
                    .padding(.horizontal, 10)
                    .background(isHeader ? Color(.secondarySystemGroupedBackground) : Color(.systemBackground))
                    .border(Color(.separator).opacity(0.2), width: 0.5)
            }
        }
    }
}
