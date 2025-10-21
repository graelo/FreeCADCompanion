import AppKit
import QuickLookThumbnailing
import ZIPFoundation
import os.log

private let logger = Logger(
    subsystem: Bundle(for: ThumbnailProvider.self).bundleIdentifier
        ?? "org.freecad.FreeCADCompanion.fallback",
    category: "PreviewProvider"
)

func extractThumbnail(from zipURL: URL) -> CGImage? {
    logger.debug(
        "Attempting to extract thumbnail from: \(zipURL.path, privacy: .public)"
    )

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
        "Started accessing security scoped resource for URL: \(zipURL.path, privacy: .public)"
    )

    // Attempt to read the images from the ZIP file
    do {
        let archive = try Archive(url: zipURL, accessMode: .read)

        let fallbackPaths = ["thumbnails/Thumbnail.png", "Thumbnail.png"]

        guard let entry = fallbackPaths.compactMap({ archive[$0] }).first else {
            return nil
        }

        var imageData = Data()
        _ = try archive.extract(
            entry,
            consumer: { data in
                imageData.append(data)
            }
        )
        // Create a direct-access data provider from the Data
        guard let dataProvider = CGDataProvider(data: imageData as CFData)
        else {
            return nil
        }
        // Create a CGImage from the PNG data
        guard
            let cgImage = CGImage(
                pngDataProviderSource: dataProvider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        else {
            return nil
        }
        return cgImage

    } catch {
        logger.error("\(error.localizedDescription)")
        return nil
    }

}

class ThumbnailProvider: QLThumbnailProvider {

    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {

        logger.debug(
            "Providing thumbnail for: \(request.fileURL.path, privacy: .public)"
        )

        guard let cgImage = extractThumbnail(from: request.fileURL) else {
            logger.warning("No valid thumbnail found; returning empty reply.")
            handler(nil, nil)
            return
        }

        let reply = QLThumbnailReply(
            contextSize: request.maximumSize,
            currentContextDrawing: { () -> Bool in
                let image = NSImage(cgImage: cgImage, size: request.maximumSize)
                image.draw(in: CGRect(origin: .zero, size: request.maximumSize))
                return true
            }
        )


        handler(reply, nil)
    }
}
