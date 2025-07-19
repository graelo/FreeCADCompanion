//
//  PreviewProvider.swift
//  Extension
//
//  Created by graelo.
//

import Cocoa
import Quartz
import UniformTypeIdentifiers
import os.log
import ZIPFoundation

private let logger = Logger(
    subsystem: Bundle(for: PreviewProvider.self).bundleIdentifier
        ?? "cc.graelo.FreeCADThumbnailPreview.fallback",
    category: "PreviewProvider")

class PreviewProvider: QLPreviewProvider, QLPreviewingController {

    func extractThumbnail(from zipURL: URL) -> CGImage? {
        logger.debug("Attempting to extract thumbnail from: \(zipURL.path, privacy: .public)")

        let didStartAccessing = zipURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                zipURL.stopAccessingSecurityScopedResource()
                logger.debug(
                    "Stopped accessing security scoped resource for URL: \(zipURL.path, privacy: .public)"
                )
            } else {
                logger.warning(
                    "Did not start accessing security scoped resource for URL: \(zipURL.path, privacy: .public)"
                )
            }
        }
        logger.debug(
            "Started accessing security scoped resource for URL: \(zipURL.path, privacy: .public)")

        // Attempt to read the images from the ZIP file
        do {
            let archive = try Archive(url: zipURL, accessMode: .read)
            
            let fallbackPaths = ["thumbnails/Thumbnail.png", "Thumbnail.png"]
            
            guard let entry = fallbackPaths.compactMap({ archive[$0] }).first else {
                return nil
            }
            
            var imageData = Data()
            _ = try archive.extract(entry, consumer: { data in
                imageData.append(data)
            })
            // Create a direct-access data provider from the Data
            guard let dataProvider = CGDataProvider(data: imageData as CFData) else {
                return nil
            }
            // Create a CGImage from the PNG data
            guard let cgImage = CGImage(pngDataProviderSource: dataProvider,
                                        decode: nil,
                                        shouldInterpolate: true,
                                        intent: .defaultIntent) else {
                return nil
            }
            return cgImage
            
        } catch {
            logger.error("\(error.localizedDescription)")
            return nil
        }
        
    }

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        logger.critical(
            "--- PreviewProvider: providePreview CALLED for \(request.fileURL.lastPathComponent, privacy: .public) ---"
        )

        let fileURL = request.fileURL
        logger.info("Received file URL: \(fileURL.path, privacy: .public)")

        guard let image = extractThumbnail(from: fileURL) else {
            let errorMessage =
                "Failed to extract thumbnail from FreeCAD file: \(fileURL.lastPathComponent)"
            logger.error("\(errorMessage, privacy: .public)")
            throw NSError(
                domain: Bundle(for: PreviewProvider.self).bundleIdentifier
                    ?? "cc.graelo.FreeCADThumbnailPreview.fallback",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: errorMessage]
            )
        }

        logger.info("Thumbnail extracted successfully. Image size: \(image.width)x\(image.height)")

        let imageSize = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
        logger.debug("Preview contextSize will be: \(imageSize.width)x\(imageSize.height)")

        // Ensure imageSize is valid and positive
        if imageSize.width <= 0 || imageSize.height <= 0 {
            let errorMessage =
                "Cannot create preview with zero or negative dimensions: \(imageSize) for file: \(fileURL.lastPathComponent)"
            logger.error("\(errorMessage, privacy: .public)")
            throw NSError(
                domain: Bundle(for: PreviewProvider.self).bundleIdentifier
                    ?? "cc.graelo.FreeCADThumbnailPreview.fallback",
                code: 1003,
                userInfo: [NSLocalizedDescriptionKey: errorMessage]
            )
        }

        let reply = QLPreviewReply(contextSize: imageSize, isBitmap: true) { context, _ in
            logger.info("Drawing block started. Drawing extracted thumbnail.")

            // Draw the extracted thumbnail image
            context.draw(image, in: CGRect(origin: .zero, size: imageSize))
            logger.debug("Thumbnail image drawn in context.")

            logger.info("Drawing block finished.")
            return
        }

        logger.notice("QLPreviewReply created. Returning reply.")
        return reply
    }
}
