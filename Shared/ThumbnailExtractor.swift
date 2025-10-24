//
//  SwiftZIPParser.swift
//  FreeCAD QuickLook Swift Implementation
//
//  Pure Swift ZIP parser for extracting thumbnails from FreeCAD (.FCStd) files
//  This removes external dependencies while maintaining modern Swift APIs
//
//  Created for integration with FreeCAD upstream
//

import Compression
import CoreGraphics
import Foundation
import ImageIO
import os.log

// MARK: - ZIP File Format Constants

private struct ZIPConstants {
    static let localFileSignature: UInt32 = 0x0403_4b50
    static let centralDirSignature: UInt32 = 0x0201_4b50
    static let endOfCentralDirSignature: UInt32 = 0x0605_4b50

    static let compressionStored: UInt16 = 0
    static let compressionDeflate: UInt16 = 8
}

// MARK: - ZIP Structures

private struct ZIPLocalFileHeader {
    let signature: UInt32
    let version: UInt16
    let flags: UInt16
    let compression: UInt16
    let modTime: UInt16
    let modDate: UInt16
    let crc32: UInt32
    let compressedSize: UInt32
    let uncompressedSize: UInt32
    let filenameLength: UInt16
    let extraFieldLength: UInt16

    static let size = 30
}

private struct ZIPCentralDirHeader {
    let signature: UInt32
    let versionMadeBy: UInt16
    let versionNeeded: UInt16
    let flags: UInt16
    let compression: UInt16
    let modTime: UInt16
    let modDate: UInt16
    let crc32: UInt32
    let compressedSize: UInt32
    let uncompressedSize: UInt32
    let filenameLength: UInt16
    let extraFieldLength: UInt16
    let commentLength: UInt16
    let diskNumber: UInt16
    let internalAttributes: UInt16
    let externalAttributes: UInt32
    let localHeaderOffset: UInt32

    static let size = 46
}

private struct ZIPEndOfCentralDir {
    let signature: UInt32
    let diskNumber: UInt16
    let centralDirDisk: UInt16
    let entriesOnDisk: UInt16
    let totalEntries: UInt16
    let centralDirSize: UInt32
    let centralDirOffset: UInt32
    let commentLength: UInt16

    static let size = 22
}

// MARK: - Error Types

enum ZIPParserError: Error, LocalizedError {
    case fileNotFound
    case invalidZipFile
    case corruptedZipFile
    case thumbnailNotFound
    case compressionUnsupported
    case decompressionFailed

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "FCStd file not found"
        case .invalidZipFile:
            return "Invalid ZIP file format"
        case .corruptedZipFile:
            return "Corrupted ZIP file"
        case .thumbnailNotFound:
            return "No thumbnail found in FCStd file"
        case .compressionUnsupported:
            return "Unsupported compression method"
        case .decompressionFailed:
            return "Failed to decompress file data"
        }
    }
}

// MARK: - Pure Swift ZIP Parser

struct SwiftZIPParser {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "org.freecad.quicklook",
        category: "SwiftZIPParser"
    )

    /// Extract thumbnail from FCStd file
    static func extractThumbnail(from fileURL: URL, maxSize: CGSize? = nil) throws -> CGImage {
        logger.debug("Extracting thumbnail from file: \(fileURL.path)")
        logger.info("=== SwiftZIPParser.extractThumbnail called ===")
        logger.info("File URL: \(fileURL.path)")
        logger.info("File exists: \(FileManager.default.fileExists(atPath: fileURL.path))")
        do {
            let isReachable = try fileURL.checkResourceIsReachable()
            logger.info("File is readable: \(isReachable)")
        } catch {
            logger.info("File is readable: false (error: \(error.localizedDescription))")
        }

        // Handle security scoped resources
        let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
        logger.info("Started accessing security scoped resource: \(didStartAccessing)")
        defer {
            if didStartAccessing {
                fileURL.stopAccessingSecurityScopedResource()
                logger.debug("Stopped accessing security scoped resource")
            }
        }

        // Read file data
        let zipData: Data
        do {
            zipData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            logger.info("Successfully read \(zipData.count) bytes from file")
        } catch {
            logger.error(
                "Failed to read file data: \(error.localizedDescription)")
            logger.error("Failed to read file data: \(error.localizedDescription)")
            throw ZIPParserError.fileNotFound
        }

        return try extractThumbnail(from: zipData, maxSize: maxSize)
    }

    /// Extract thumbnail from ZIP data
    static func extractThumbnail(from zipData: Data, maxSize: CGSize? = nil) throws -> CGImage {
        logger.info("=== Processing ZIP data ===")
        logger.info("ZIP data size: \(zipData.count) bytes")

        guard zipData.count >= ZIPLocalFileHeader.size else {
            logger.error("ZIP data too small")
            logger.error("ZIP data too small: \(zipData.count) < \(ZIPLocalFileHeader.size)")
            throw ZIPParserError.invalidZipFile
        }

        // Verify ZIP signature
        let signature = zipData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        logger.info("ZIP signature: 0x\(String(signature, radix: 16))")
        guard signature == ZIPConstants.localFileSignature else {
            logger.error("Invalid ZIP signature: 0x\(String(signature, radix: 16))")
            logger.error(
                "Invalid ZIP signature: 0x\(String(signature, radix: 16)), expected: 0x\(String(ZIPConstants.localFileSignature, radix: 16))"
            )
            throw ZIPParserError.invalidZipFile
        }

        // Find end of central directory
        logger.info("Searching for end of central directory...")
        guard let endOfCentralDir = findEndOfCentralDirectory(in: zipData) else {
            logger.error("Could not find end of central directory")
            throw ZIPParserError.corruptedZipFile
        }
        logger.info("Found end of central directory with \(endOfCentralDir.totalEntries) entries")

        // Look for thumbnail files
        let thumbnailPaths = ["thumbnails/Thumbnail.png", "Thumbnail.png"]
        logger.info("Searching for thumbnail files: \(thumbnailPaths)")

        for thumbnailPath in thumbnailPaths {
            logger.info("Trying path: \(thumbnailPath)")
            if let thumbnailData = try? extractFile(
                from: zipData,
                endOfCentralDir: endOfCentralDir,
                filename: thumbnailPath
            ) {
                logger.debug("Found thumbnail at path: \(thumbnailPath)")
                logger.info(
                    "Found thumbnail at path: \(thumbnailPath), size: \(thumbnailData.count) bytes")

                if let image = createImage(from: thumbnailData, maxSize: maxSize) {
                    logger.debug("Successfully created CGImage from thumbnail data")
                    logger.info("Successfully created CGImage from thumbnail data")
                    return image
                } else {
                    logger.warning(
                        "Failed to create CGImage from thumbnail data at path: \(thumbnailPath)")
                }
            } else {
                logger.info("No thumbnail found at path: \(thumbnailPath)")
            }
        }

        logger.info("No thumbnail found in FCStd file")
        logger.warning("No valid thumbnail found in FCStd file")
        throw ZIPParserError.thumbnailNotFound
    }

    /// Validate if file is a valid FCStd (ZIP) file
    static func isValidFCStdFile(at url: URL) -> Bool {
        guard let headerData = try? Data(contentsOf: url, options: .uncached),
            headerData.count >= 4
        else {
            return false
        }

        let signature = headerData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        return signature == ZIPConstants.localFileSignature
    }
}

// MARK: - Private ZIP Parsing Methods

extension SwiftZIPParser {

    /// Find the end of central directory record
    fileprivate static func findEndOfCentralDirectory(in data: Data) -> ZIPEndOfCentralDir? {
        let dataCount = data.count
        guard dataCount >= ZIPEndOfCentralDir.size else { return nil }

        let searchStart = dataCount - ZIPEndOfCentralDir.size
        let maxSearch = min(searchStart, 65535 + ZIPEndOfCentralDir.size)  // Max comment length

        for i in 0...maxSearch {
            let pos = searchStart - i
            guard pos + ZIPEndOfCentralDir.size <= dataCount else { continue }

            let signature = data.subdata(in: pos..<(pos + 4))
                .withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }

            if signature == ZIPConstants.endOfCentralDirSignature {
                return parseEndOfCentralDir(from: data, at: pos)
            }
        }

        return nil
    }

    /// Parse end of central directory structure
    fileprivate static func parseEndOfCentralDir(from data: Data, at offset: Int)
        -> ZIPEndOfCentralDir
    {
        let eocdData = data.subdata(in: offset..<(offset + ZIPEndOfCentralDir.size))

        return ZIPEndOfCentralDir(
            signature: readUInt32(from: eocdData, at: 0),
            diskNumber: readUInt16(from: eocdData, at: 4),
            centralDirDisk: readUInt16(from: eocdData, at: 6),
            entriesOnDisk: readUInt16(from: eocdData, at: 8),
            totalEntries: readUInt16(from: eocdData, at: 10),
            centralDirSize: readUInt32(from: eocdData, at: 12),
            centralDirOffset: readUInt32(from: eocdData, at: 16),
            commentLength: readUInt16(from: eocdData, at: 20)
        )
    }

    /// Extract a specific file from the ZIP data
    fileprivate static func extractFile(
        from zipData: Data,
        endOfCentralDir: ZIPEndOfCentralDir,
        filename: String
    ) throws -> Data {

        let filenameData = filename.data(using: .utf8)!
        let centralDirOffset = Int(endOfCentralDir.centralDirOffset)
        let totalEntries = Int(endOfCentralDir.totalEntries)

        var currentOffset = centralDirOffset

        // Parse central directory entries
        for _ in 0..<totalEntries {
            guard currentOffset + ZIPCentralDirHeader.size <= zipData.count else {
                break
            }

            let centralHeader = parseCentralDirHeader(from: zipData, at: currentOffset)

            guard centralHeader.signature == ZIPConstants.centralDirSignature else {
                break
            }

            // Check if this is our target file
            let filenameOffset = currentOffset + ZIPCentralDirHeader.size
            let filenameLength = Int(centralHeader.filenameLength)

            guard filenameOffset + filenameLength <= zipData.count else {
                throw ZIPParserError.corruptedZipFile
            }

            let entryFilenameData = zipData.subdata(
                in: filenameOffset..<(filenameOffset + filenameLength))

            if entryFilenameData == filenameData {
                // Found our file, extract it
                return try extractFileData(from: zipData, centralHeader: centralHeader)
            }

            // Move to next central directory entry
            currentOffset +=
                ZIPCentralDirHeader.size + Int(centralHeader.filenameLength)
                + Int(centralHeader.extraFieldLength) + Int(centralHeader.commentLength)
        }

        throw ZIPParserError.thumbnailNotFound
    }

    /// Parse central directory header structure
    fileprivate static func parseCentralDirHeader(from data: Data, at offset: Int)
        -> ZIPCentralDirHeader
    {
        let headerData = data.subdata(in: offset..<(offset + ZIPCentralDirHeader.size))

        return ZIPCentralDirHeader(
            signature: readUInt32(from: headerData, at: 0),
            versionMadeBy: readUInt16(from: headerData, at: 4),
            versionNeeded: readUInt16(from: headerData, at: 6),
            flags: readUInt16(from: headerData, at: 8),
            compression: readUInt16(from: headerData, at: 10),
            modTime: readUInt16(from: headerData, at: 12),
            modDate: readUInt16(from: headerData, at: 14),
            crc32: readUInt32(from: headerData, at: 16),
            compressedSize: readUInt32(from: headerData, at: 20),
            uncompressedSize: readUInt32(from: headerData, at: 24),
            filenameLength: readUInt16(from: headerData, at: 28),
            extraFieldLength: readUInt16(from: headerData, at: 30),
            commentLength: readUInt16(from: headerData, at: 32),
            diskNumber: readUInt16(from: headerData, at: 34),
            internalAttributes: readUInt16(from: headerData, at: 36),
            externalAttributes: readUInt32(from: headerData, at: 38),
            localHeaderOffset: readUInt32(from: headerData, at: 42)
        )
    }

    /// Extract file data using local header information
    fileprivate static func extractFileData(from zipData: Data, centralHeader: ZIPCentralDirHeader)
        throws -> Data
    {
        let localHeaderOffset = Int(centralHeader.localHeaderOffset)

        guard localHeaderOffset + ZIPLocalFileHeader.size <= zipData.count else {
            throw ZIPParserError.corruptedZipFile
        }

        let localHeader = parseLocalFileHeader(from: zipData, at: localHeaderOffset)

        guard localHeader.signature == ZIPConstants.localFileSignature else {
            throw ZIPParserError.corruptedZipFile
        }

        // Calculate data offset
        let dataOffset =
            localHeaderOffset + ZIPLocalFileHeader.size + Int(localHeader.filenameLength)
            + Int(localHeader.extraFieldLength)

        guard dataOffset + Int(localHeader.compressedSize) <= zipData.count else {
            throw ZIPParserError.corruptedZipFile
        }

        let compressedData = zipData.subdata(
            in: dataOffset..<(dataOffset + Int(localHeader.compressedSize)))

        // Handle different compression methods
        switch localHeader.compression {
        case ZIPConstants.compressionStored:
            return compressedData

        case ZIPConstants.compressionDeflate:
            return try deflateDecompress(
                data: compressedData,
                expectedSize: Int(localHeader.uncompressedSize)
            )

        default:
            logger.debug("Unsupported compression method: \(localHeader.compression)")
            throw ZIPParserError.compressionUnsupported
        }
    }

    /// Parse local file header structure
    fileprivate static func parseLocalFileHeader(from data: Data, at offset: Int)
        -> ZIPLocalFileHeader
    {
        let headerData = data.subdata(in: offset..<(offset + ZIPLocalFileHeader.size))

        return ZIPLocalFileHeader(
            signature: readUInt32(from: headerData, at: 0),
            version: readUInt16(from: headerData, at: 4),
            flags: readUInt16(from: headerData, at: 6),
            compression: readUInt16(from: headerData, at: 8),
            modTime: readUInt16(from: headerData, at: 10),
            modDate: readUInt16(from: headerData, at: 12),
            crc32: readUInt32(from: headerData, at: 14),
            compressedSize: readUInt32(from: headerData, at: 18),
            uncompressedSize: readUInt32(from: headerData, at: 22),
            filenameLength: readUInt16(from: headerData, at: 26),
            extraFieldLength: readUInt16(from: headerData, at: 28)
        )
    }

    /// Decompress deflate compressed data using Swift Compression framework
    fileprivate static func deflateDecompress(data: Data, expectedSize: Int) throws -> Data {
        guard !data.isEmpty else {
            throw ZIPParserError.decompressionFailed
        }

        // Allocate output buffer
        var outputBuffer = Data(count: expectedSize)

        let actualSize = try data.withUnsafeBytes { inputBytes in
            try outputBuffer.withUnsafeMutableBytes { outputBytes in
                let inputPtr = inputBytes.bindMemory(to: UInt8.self)
                let outputPtr = outputBytes.bindMemory(to: UInt8.self)

                // Use compression_decode_buffer for raw deflate data
                let result = compression_decode_buffer(
                    outputPtr.baseAddress!, expectedSize,
                    inputPtr.baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )

                guard result > 0 else {
                    throw ZIPParserError.decompressionFailed
                }

                return result
            }
        }

        // Adjust size if needed
        if actualSize != expectedSize {
            logger.debug("Decompressed size mismatch: expected \(expectedSize), got \(actualSize)")
            outputBuffer = outputBuffer.prefix(actualSize)
        }

        logger.debug("Successfully decompressed \(data.count) bytes to \(outputBuffer.count) bytes")
        return outputBuffer
    }

    /// Create CGImage from PNG data
    fileprivate static func createImage(from pngData: Data, maxSize: CGSize? = nil) -> CGImage? {
        guard !pngData.isEmpty else { return nil }

        guard let dataProvider = CGDataProvider(data: pngData as CFData) else {
            return nil
        }

        guard
            let image = CGImage(
                pngDataProviderSource: dataProvider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        else {
            logger.error("Failed to create CGImage from PNG data")
            return nil
        }

        // If no maxSize specified, return original image
        guard let maxSize = maxSize else {
            return image
        }

        // Scale the image to fit within maxSize while maintaining aspect ratio
        let originalSize = CGSize(width: image.width, height: image.height)
        let scaledSize = scaleToFit(originalSize: originalSize, maxSize: maxSize)

        return scaleImage(image, to: scaledSize)
    }

    // MARK: - Helper Functions for Safe Memory Access

    /// Safely read UInt32 from Data at offset
    fileprivate static func readUInt32(from data: Data, at offset: Int) -> UInt32 {
        let subdata = data.subdata(in: offset..<(offset + 4))
        return subdata.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    }

    /// Safely read UInt16 from Data at offset
    fileprivate static func readUInt16(from data: Data, at offset: Int) -> UInt16 {
        let subdata = data.subdata(in: offset..<(offset + 2))
        return subdata.withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
    }

    /// Calculate size that fits within maxSize while maintaining aspect ratio
    fileprivate static func scaleToFit(originalSize: CGSize, maxSize: CGSize) -> CGSize {
        let widthRatio = maxSize.width / originalSize.width
        let heightRatio = maxSize.height / originalSize.height
        let scaleFactor = min(widthRatio, heightRatio)

        return CGSize(
            width: originalSize.width * scaleFactor,
            height: originalSize.height * scaleFactor
        )
    }

    /// Scale CGImage to specified size
    fileprivate static func scaleImage(_ image: CGImage, to size: CGSize) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard
            let context = CGContext(
                data: nil,
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            )
        else {
            logger.error("Failed to create CGContext for image scaling")
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))

        return context.makeImage()
    }
}
