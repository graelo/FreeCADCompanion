import Foundation
import CoreGraphics
import ZIPFoundation
import os.log

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "org.freecad.FreeCADCompanion.fallback",
    category: "ThumbnailExtractor"
)

func extractThumbnail(from zipURL: URL) -> CGImage? {
    logger.debug("Attempting to extract thumbnail from: \(zipURL.path, privacy: .public)")

    let didStartAccessing = zipURL.startAccessingSecurityScopedResource()
    defer {
        if didStartAccessing {
            zipURL.stopAccessingSecurityScopedResource()
            logger.debug("Stopped accessing security scoped resource for URL: \(zipURL.path, privacy: .public)")
        } else {
            logger.warning("Did not start accessing security scoped resource for URL: \(zipURL.path, privacy: .public)")
        }
    }
    logger.debug("Started accessing security scoped resource for URL: \(zipURL.path, privacy: .public)")

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

        guard let dataProvider = CGDataProvider(data: imageData as CFData) else {
            return nil
        }

        guard let cgImage = CGImage(
            pngDataProviderSource: dataProvider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            return nil
        }

        return cgImage
    } catch {
        logger.error("\(error.localizedDescription, privacy: .public)")
        return nil
    }
}

