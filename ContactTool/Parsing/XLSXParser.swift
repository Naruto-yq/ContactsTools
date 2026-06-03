import Foundation

enum XLSXParser {
    static func parse(data: Data) throws -> [[String]] {
        let archive = try ZIPArchive(data: data)
        let workbookXML = try archive.string(path: "xl/workbook.xml")
        let relationshipID = try firstSheetRelationshipID(from: workbookXML)
        let relsXML = try archive.string(path: "xl/_rels/workbook.xml.rels")
        let sheetPath = try sheetPath(for: relationshipID, relsXML: relsXML)
        let sharedStrings = archive.contains("xl/sharedStrings.xml")
            ? try SharedStringsXMLParser.parse(archive.string(path: "xl/sharedStrings.xml"))
            : []
        let sheetXML = try archive.string(path: sheetPath)
        return try SheetXMLParser.parse(sheetXML, sharedStrings: sharedStrings)
    }

    private static func firstSheetRelationshipID(from xml: String) throws -> String {
        guard let sheetTag = firstTag(named: "sheet", in: xml),
              let relationshipID = attribute("r:id", in: sheetTag) else {
            throw ContactToolError.parseFailure(AppText.localized("Excel 工作簿中未找到第一张工作表。", "The first worksheet was not found in the Excel workbook."))
        }
        return relationshipID
    }

    private static func sheetPath(for relationshipID: String, relsXML: String) throws -> String {
        for tag in tags(named: "Relationship", in: relsXML) {
            guard attribute("Id", in: tag) == relationshipID,
                  let target = attribute("Target", in: tag) else { continue }

            if target.hasPrefix("/") { return String(target.dropFirst()) }
            if target.hasPrefix("xl/") { return target }
            return "xl/" + target
        }

        throw ContactToolError.parseFailure(AppText.localizedFormat("Excel 工作表关系文件缺少 %@。", "The Excel worksheet relationship file is missing %@.", relationshipID))
    }

    private static func firstTag(named name: String, in xml: String) -> String? {
        tags(named: name, in: xml).first
    }

    private static func tags(named name: String, in xml: String) -> [String] {
        let pattern = "<" + name + "\\b[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        return regex.matches(in: xml, range: range).compactMap { match in
            guard let range = Range(match.range, in: xml) else { return nil }
            return String(xml[range])
        }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\s*=\\s*\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        guard let match = regex.firstMatch(in: tag, range: range),
              let valueRange = Range(match.range(at: 1), in: tag) else { return nil }
        return String(tag[valueRange])
    }
}

private final class SharedStringsXMLParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var current = ""
    private var isInsideStringItem = false
    private var isInsideText = false

    static func parse(_ xml: String) throws -> [String] {
        guard let data = xml.data(using: .utf8) else { return [] }
        let delegate = SharedStringsXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw ContactToolError.parseFailure(AppText.localized("Excel 共享字符串解析失败。", "Failed to parse Excel shared strings."))
        }
        return delegate.strings
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "si":
            isInsideStringItem = true
            current = ""
        case "t":
            if isInsideStringItem { isInsideText = true }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideStringItem && isInsideText { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "t":
            isInsideText = false
        case "si":
            strings.append(current)
            current = ""
            isInsideStringItem = false
        default:
            break
        }
    }
}

private final class SheetXMLParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private var rows: [Int: [Int: String]] = [:]
    private var currentRowIndex = 1
    private var currentColumnIndex = 0
    private var currentType = ""
    private var valueText = ""
    private var inlineText = ""
    private var isInsideValue = false
    private var isInsideInlineText = false

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    static func parse(_ xml: String, sharedStrings: [String]) throws -> [[String]] {
        guard let data = xml.data(using: .utf8) else { return [] }
        let delegate = SheetXMLParser(sharedStrings: sharedStrings)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw ContactToolError.parseFailure(AppText.localized("Excel 工作表解析失败。", "Failed to parse the Excel worksheet."))
        }
        return delegate.makeRows()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "row":
            if let row = attributeDict["r"], let number = Int(row) { currentRowIndex = number }
        case "c":
            currentType = attributeDict["t"] ?? ""
            valueText = ""
            inlineText = ""
            if let reference = attributeDict["r"] {
                currentColumnIndex = Self.columnIndex(from: reference)
                currentRowIndex = Self.rowIndex(from: reference) ?? currentRowIndex
            }
        case "v":
            isInsideValue = true
        case "t":
            if currentType == "inlineStr" { isInsideInlineText = true }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideValue { valueText += string }
        if isInsideInlineText { inlineText += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "v":
            isInsideValue = false
        case "t":
            isInsideInlineText = false
        case "c":
            let value = resolvedValue()
            if !value.isEmpty {
                var row = rows[currentRowIndex, default: [:]]
                row[currentColumnIndex] = value
                rows[currentRowIndex] = row
            }
        default:
            break
        }
    }

    private func resolvedValue() -> String {
        let raw = valueText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch currentType {
        case "s":
            guard let index = Int(raw), sharedStrings.indices.contains(index) else { return raw }
            return sharedStrings[index].trimmingCharacters(in: .whitespacesAndNewlines)
        case "inlineStr":
            return inlineText.trimmingCharacters(in: .whitespacesAndNewlines)
        case "b":
            return raw == "1" ? "TRUE" : "FALSE"
        default:
            return raw
        }
    }

    private func makeRows() -> [[String]] {
        let sortedRowNumbers = rows.keys.sorted()
        let maxColumn = rows.values.flatMap { $0.keys }.max() ?? -1
        guard maxColumn >= 0 else { return [] }

        return sortedRowNumbers.map { rowNumber in
            let values = rows[rowNumber] ?? [:]
            return (0...maxColumn).map { column in values[column] ?? "" }
        }.filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    private static func columnIndex(from reference: String) -> Int {
        var result = 0
        for scalar in reference.unicodeScalars {
            let value = scalar.value
            guard (value >= 65 && value <= 90) || (value >= 97 && value <= 122) else { break }
            let upper = value >= 97 ? value - 32 : value
            result = result * 26 + Int(upper - 64)
        }
        return max(0, result - 1)
    }

    private static func rowIndex(from reference: String) -> Int? {
        Int(reference.filter { $0.isNumber })
    }
}
