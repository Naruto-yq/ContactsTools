import Foundation

struct ZIPArchive {
    struct Entry {
        let name: String
        let compressionMethod: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private let data: Data
    private let entries: [String: Entry]

    init(data: Data) throws {
        self.data = data
        self.entries = try ZIPArchive.readCentralDirectory(from: data)
    }

    func contains(_ path: String) -> Bool {
        entries[path] != nil
    }

    func string(path: String) throws -> String {
        let data = try fileData(path: path)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ContactToolError.parseFailure(AppText.localizedFormat("无法以 UTF-8 读取 %@。", "Unable to read %@ as UTF-8.", path))
        }
        return text
    }

    func fileData(path: String) throws -> Data {
        guard let entry = entries[path] else {
            throw ContactToolError.parseFailure(AppText.localizedFormat("Excel 文件缺少 %@。", "The Excel file is missing %@.", path))
        }

        guard data.uint32LE(at: entry.localHeaderOffset) == 0x04034b50 else {
            throw ContactToolError.parseFailure(AppText.localized("Excel ZIP 本地文件头异常。", "The Excel ZIP local file header is invalid."))
        }

        let nameLength = Int(data.uint16LE(at: entry.localHeaderOffset + 26))
        let extraLength = Int(data.uint16LE(at: entry.localHeaderOffset + 28))
        let dataStart = entry.localHeaderOffset + 30 + nameLength + extraLength
        let dataEnd = dataStart + entry.compressedSize
        guard dataStart >= 0, dataEnd <= data.count else {
            throw ContactToolError.parseFailure(AppText.localized("Excel ZIP 数据区越界。", "The Excel ZIP data range is out of bounds."))
        }

        let compressed = data.subdata(in: dataStart..<dataEnd)
        switch entry.compressionMethod {
        case 0:
            return compressed
        case 8:
            return try inflateRawDeflate(compressed, uncompressedSize: entry.uncompressedSize)
        default:
            throw ContactToolError.parseFailure(AppText.localizedFormat("暂不支持 Excel ZIP 压缩方式 %d。", "Excel ZIP compression method %d is not supported yet.", entry.compressionMethod))
        }
    }

    private static func readCentralDirectory(from data: Data) throws -> [String: Entry] {
        let eocdOffset = try findEndOfCentralDirectory(in: data)
        let entryCount = Int(data.uint16LE(at: eocdOffset + 10))
        let centralOffset = Int(data.uint32LE(at: eocdOffset + 16))
        var offset = centralOffset
        var entries: [String: Entry] = [:]

        for _ in 0..<entryCount {
            guard data.uint32LE(at: offset) == 0x02014b50 else {
                throw ContactToolError.parseFailure(AppText.localized("Excel ZIP 中央目录异常。", "The Excel ZIP central directory is invalid."))
            }

            let method = data.uint16LE(at: offset + 10)
            let compressedSize = Int(data.uint32LE(at: offset + 20))
            let uncompressedSize = Int(data.uint32LE(at: offset + 24))
            let nameLength = Int(data.uint16LE(at: offset + 28))
            let extraLength = Int(data.uint16LE(at: offset + 30))
            let commentLength = Int(data.uint16LE(at: offset + 32))
            let localHeaderOffset = Int(data.uint32LE(at: offset + 42))
            let nameStart = offset + 46
            let nameEnd = nameStart + nameLength

            guard nameEnd <= data.count else {
                throw ContactToolError.parseFailure(AppText.localized("Excel ZIP 文件名越界。", "The Excel ZIP file name range is out of bounds."))
            }

            let nameData = data.subdata(in: nameStart..<nameEnd)
            guard let name = String(data: nameData, encoding: .utf8) else {
                throw ContactToolError.parseFailure(AppText.localized("Excel ZIP 文件名编码异常。", "The Excel ZIP file name encoding is invalid."))
            }

            entries[name] = Entry(name: name, compressionMethod: method, compressedSize: compressedSize, uncompressedSize: uncompressedSize, localHeaderOffset: localHeaderOffset)
            offset = nameEnd + extraLength + commentLength
        }

        return entries
    }

    private static func findEndOfCentralDirectory(in data: Data) throws -> Int {
        guard data.count >= 22 else {
            throw ContactToolError.parseFailure(AppText.localized("Excel ZIP 文件过小。", "The Excel ZIP file is too small."))
        }

        let minimum = max(0, data.count - 65_557)
        var offset = data.count - 22
        while offset >= minimum {
            if data.uint32LE(at: offset) == 0x06054b50 {
                return offset
            }
            offset -= 1
        }

        throw ContactToolError.parseFailure(AppText.localized("未找到 Excel ZIP 目录。", "The Excel ZIP directory was not found."))
    }

    private func inflateRawDeflate(_ compressed: Data, uncompressedSize: Int) throws -> Data {
        if uncompressedSize == 0 { return Data() }
        var output = Data(count: uncompressedSize)

        let outputSize = output.count
        let compressedSize = compressed.count
        let status: Int32 = output.withUnsafeMutableBytes { outputPointer in
            compressed.withUnsafeBytes { inputPointer in
                guard let inputBase = inputPointer.bindMemory(to: UInt8.self).baseAddress,
                      let outputBase = outputPointer.bindMemory(to: UInt8.self).baseAddress else {
                    return -1
                }
                return contacttool_inflate_raw(inputBase, compressedSize, outputBase, outputSize)
            }
        }

        guard status == 0 else {
            throw ContactToolError.parseFailure(AppText.localizedFormat("Excel ZIP 解压失败，状态码 %d。", "Excel ZIP decompression failed with status code %d.", status))
        }

        return output
    }
}

private extension Data {
    func uint16LE(at offset: Int) -> UInt16 {
        guard offset + 1 < count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32LE(at offset: Int) -> UInt32 {
        guard offset + 3 < count else { return 0 }
        return UInt32(self[offset]) |
            (UInt32(self[offset + 1]) << 8) |
            (UInt32(self[offset + 2]) << 16) |
            (UInt32(self[offset + 3]) << 24)
    }
}
