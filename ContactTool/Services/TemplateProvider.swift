import Foundation

enum TemplateProvider {
    static var headers: [String] { AppText.isChinese ? ["姓名", "手机号", "邮箱", "公司", "地址", "备注"] : ["Name", "Phone", "Email", "Company", "Address", "Note"] }
    static var rows: [[String]] {
        AppText.isChinese ? [
            ["张三", "13800138000", "test@example.com", "ABC公司", "上海市浦东新区示例路 100 号", "客户"],
            ["李四", "13900139000", "lisi@example.com", "示例学校", "北京市海淀区示例街 8 号", "家长"]
        ] : [
            ["Alex Chen", "13800138000", "alex@example.com", "ABC Company", "100 Sample Road, Shanghai", "Customer"],
            ["Taylor Lee", "13900139000", "taylor@example.com", "Sample School", "8 Example Street, Beijing", "Parent"]
        ]
    }

    static func csv(includeBOM: Bool) -> String {
        let allRows = [headers] + rows
        let body = allRows.map { row in row.map(escapeCSVCell).joined(separator: ",") }.joined(separator: "\n")
        return includeBOM ? "\u{feff}" + body : body
    }

    static func writeTemporaryCSV() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("contacts_template.csv")
        try csv(includeBOM: true).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func escapeCSVCell(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

enum SpreadsheetExporter {
    static var headers: [String] { TemplateProvider.headers }

    static func writeCSV(contacts: [ContactRecord], fileName: String) throws -> URL {
        let csvRows = [headers] + rows(from: contacts)
        let text = "\u{feff}" + csvRows.map { row in row.map(TemplateProvider.escapeCSVCell).joined(separator: ",") }.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func writeXLSX(contacts: [ContactRecord], fileName: String) throws -> URL {
        let tableRows = [headers] + rows(from: contacts)
        var zip = ZIPWriter()
        zip.addFile(path: "[Content_Types].xml", data: contentTypesXML.data(using: .utf8)!)
        zip.addFile(path: "_rels/.rels", data: packageRelationshipsXML.data(using: .utf8)!)
        zip.addFile(path: "xl/workbook.xml", data: workbookXML.data(using: .utf8)!)
        zip.addFile(path: "xl/_rels/workbook.xml.rels", data: workbookRelationshipsXML.data(using: .utf8)!)
        zip.addFile(path: "xl/worksheets/sheet1.xml", data: sheetXML(rows: tableRows).data(using: .utf8)!)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try zip.finalize().write(to: url)
        return url
    }

    static func rows(from contacts: [ContactRecord]) -> [[String]] {
        contacts.map { [$0.name, $0.phone, $0.email, $0.company, $0.address, $0.note] }
    }

    private static func sheetXML(rows: [[String]]) -> String {
        let rowXML = rows.enumerated().map { rowIndex, row in
            let rowNumber = rowIndex + 1
            let cells = row.enumerated().map { columnIndex, value in
                let ref = FieldDetector.columnLabel(for: columnIndex) + "\(rowNumber)"
                return "<c r=\"\(ref)\" t=\"inlineStr\"><is><t>\(xmlEscape(value))</t></is></c>"
            }.joined()
            return "<row r=\"\(rowNumber)\">\(cells)</row>"
        }.joined()

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>\(rowXML)</sheetData></worksheet>
        """
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>
    """

    private static let packageRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
    """

    private static let workbookXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Contacts" sheetId="1" r:id="rId1"/></sheets></workbook>
    """

    private static let workbookRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>
    """
}

private struct ZIPWriter {
    private struct Entry {
        let path: String
        let crc: UInt32
        let size: UInt32
        let offset: UInt32
    }

    private var data = Data()
    private var entries: [Entry] = []

    mutating func addFile(path: String, data fileData: Data) {
        let nameData = Data(path.utf8)
        let offset = UInt32(data.count)
        let crc = CRC32.checksum(fileData)
        let size = UInt32(fileData.count)

        data.appendUInt32LE(0x04034b50)
        data.appendUInt16LE(20)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt32LE(crc)
        data.appendUInt32LE(size)
        data.appendUInt32LE(size)
        data.appendUInt16LE(UInt16(nameData.count))
        data.appendUInt16LE(0)
        data.append(nameData)
        data.append(fileData)

        entries.append(Entry(path: path, crc: crc, size: size, offset: offset))
    }

    mutating func finalize() -> Data {
        let centralOffset = UInt32(data.count)
        for entry in entries {
            let nameData = Data(entry.path.utf8)
            data.appendUInt32LE(0x02014b50)
            data.appendUInt16LE(20)
            data.appendUInt16LE(20)
            data.appendUInt16LE(0)
            data.appendUInt16LE(0)
            data.appendUInt16LE(0)
            data.appendUInt16LE(0)
            data.appendUInt32LE(entry.crc)
            data.appendUInt32LE(entry.size)
            data.appendUInt32LE(entry.size)
            data.appendUInt16LE(UInt16(nameData.count))
            data.appendUInt16LE(0)
            data.appendUInt16LE(0)
            data.appendUInt16LE(0)
            data.appendUInt16LE(0)
            data.appendUInt32LE(0)
            data.appendUInt32LE(entry.offset)
            data.append(nameData)
        }
        let centralSize = UInt32(data.count) - centralOffset
        data.appendUInt32LE(0x06054b50)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt16LE(UInt16(entries.count))
        data.appendUInt16LE(UInt16(entries.count))
        data.appendUInt32LE(centralSize)
        data.appendUInt32LE(centralOffset)
        data.appendUInt16LE(0)
        return data
    }
}

private enum CRC32 {
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xff)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xffff_ffff
    }

    private static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            crc = (crc & 1) == 1 ? 0xedb8_8320 ^ (crc >> 1) : crc >> 1
        }
        return crc
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}
