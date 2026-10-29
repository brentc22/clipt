import AppKit
import ImageIO

/// Source-app icons, keyed by bundle id. Small and bounded: rows only ever need a few dozen.
@MainActor
enum AppIcons {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 64
        return c
    }()

    private static let fallback: NSImage = {
        let image = NSWorkspace.shared.icon(for: .applicationBundle)
        image.size = NSSize(width: 32, height: 32)
        return image
    }()

    static func icon(for bundleID: String?) -> NSImage {
        guard let bundleID else { return fallback }
        if let hit = cache.object(forKey: bundleID as NSString) { return hit }
        let image: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
            image.size = NSSize(width: 32, height: 32)
        } else {
            image = fallback
        }
        cache.setObject(image, forKey: bundleID as NSString)
        return image
    }
}

/// Thumbnails decoded from the stored 256 px PNGs, keyed by file and size. Decoding
/// happens off the main thread; the main thread only ever reads the memory cache.
/// Bounded by bytes: row-sized entries are about 16 KB, so this holds a few hundred.
@MainActor
enum Thumbnails {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.totalCostLimit = 4 * 1_048_576
        return c
    }()

    private static func key(_ url: URL, _ maxPixel: Int) -> NSString { "\(maxPixel)|\(url.path)" as NSString }

    /// Memory only, never the disk.
    static func cached(_ url: URL, maxPixel: Int) -> NSImage? { cache.object(forKey: key(url, maxPixel)) }

    /// Decodes off main on a miss. Point size is half the pixel size (Retina).
    static func load(_ url: URL, maxPixel: Int) async -> NSImage? {
        if let hit = cached(url, maxPixel: maxPixel) { return hit }
        guard let cg = await Task.detached(priority: .userInitiated, operation: { downsample(url, maxPixel: maxPixel) }).value
        else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
        cache.setObject(image, forKey: key(url, maxPixel), cost: cg.width * cg.height * 4)
        return image
    }

    nonisolated static func downsample(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return downsample(src, maxPixel: maxPixel)
    }

    nonisolated static func downsample(_ data: Data, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return downsample(src, maxPixel: maxPixel)
    }

    nonisolated private static func downsample(_ src: CGImageSource, maxPixel: Int) -> CGImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}
