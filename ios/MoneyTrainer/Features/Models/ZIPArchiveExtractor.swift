import Foundation

struct ZIPArchiveExtractor: Sendable {
    private let localFileSignature: UInt32 = 0x0403_4B50
    private let centralDirectorySignature: UInt32 = 0x0201_4B50
    private let endOfCentralDirectorySignature: UInt32 = 0x0605_4B50

    func extract(data: Data, to destination: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        var offset = 0

        while offset + 4 <= data.count {
            let signature: UInt32 = try readInteger(data, at: offset)
            if signature == centralDirectorySignature || signature == endOfCentralDirectorySignature {
                return
            }
            guard signature == localFileSignature, offset + 30 <= data.count else {
                throw ZIPArchiveError.invalidArchive
            }

            let flags: UInt16 = try readInteger(data, at: offset + 6)
            guard flags & 0x0001 == 0 else {
                throw ZIPArchiveError.unsupportedFeature("encrypted entry")
            }
            guard flags & 0x0008 == 0 else {
                throw ZIPArchiveError.unsupportedFeature("data descriptor")
            }

            let compressionMethod: UInt16 = try readInteger(data, at: offset + 8)
            let compressedSize: UInt32 = try readInteger(data, at: offset + 18)
            let uncompressedSize: UInt32 = try readInteger(data, at: offset + 22)
            let nameLength: UInt16 = try readInteger(data, at: offset + 26)
            let extraLength: UInt16 = try readInteger(data, at: offset + 28)
            let nameStart = offset + 30
            let nameEnd = nameStart + Int(nameLength)
            let contentStart = nameEnd + Int(extraLength)
            let contentEnd = contentStart + Int(compressedSize)
            guard nameEnd <= data.count, contentEnd <= data.count else {
                throw ZIPArchiveError.invalidArchive
            }

            guard let name = String(data: data[nameStart..<nameEnd], encoding: .utf8) else {
                throw ZIPArchiveError.invalidArchive
            }
            let outputURL = try safeOutputURL(for: name, destination: destination)
            if name.hasSuffix("/") {
                try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)
            } else {
                try fileManager.createDirectory(
                    at: outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let compressed = Data(data[contentStart..<contentEnd])
                let contents: Data
                switch compressionMethod {
                case 0:
                    contents = compressed
                case 8:
                    contents = try (compressed as NSData).decompressed(using: .zlib) as Data
                default:
                    throw ZIPArchiveError.unsupportedFeature("compression method \(compressionMethod)")
                }
                guard contents.count == Int(uncompressedSize) else {
                    throw ZIPArchiveError.invalidArchive
                }
                try contents.write(to: outputURL, options: .atomic)
            }
            offset = contentEnd
        }
        throw ZIPArchiveError.invalidArchive
    }

    private func safeOutputURL(for name: String, destination: URL) throws -> URL {
        let components = name.split(separator: "/", omittingEmptySubsequences: true)
        guard !name.hasPrefix("/"),
              !components.contains(".."),
              !components.contains(".") else {
            throw ZIPArchiveError.unsafePath(name)
        }
        let output = components.reduce(destination) { partial, component in
            partial.appending(path: String(component))
        }
        let destinationPath = destination.standardizedFileURL.path
        let outputPath = output.standardizedFileURL.path
        guard outputPath == destinationPath || outputPath.hasPrefix(destinationPath + "/") else {
            throw ZIPArchiveError.unsafePath(name)
        }
        return output
    }

    private func readInteger<Value: FixedWidthInteger>(_ data: Data, at offset: Int) throws -> Value {
        guard offset >= 0, offset + MemoryLayout<Value>.size <= data.count else {
            throw ZIPArchiveError.invalidArchive
        }
        return data.withUnsafeBytes { rawBuffer in
            rawBuffer.loadUnaligned(fromByteOffset: offset, as: Value.self).littleEndian
        }
    }
}
