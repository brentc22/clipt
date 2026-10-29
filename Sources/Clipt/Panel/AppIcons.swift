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

/// Row-sized thumbnails decoded from the stored 256 px PNGs. Downsampled to what a row
/// draws (about 6 KB each), and dropped when the panel closes.
@MainActor
enum Thumbnails {
    private static let cache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.countLimit = 120
        return c
    }()

    /// `maxPixel` is the longest side in pixels.
    static func image(at url: URL, maxPixel: Int = 64) -> NSImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        guard let cg = downsample(url, maxPixel: maxPixel) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
        cache.setObject(image, forKey: url as NSURL)
        return image
    }

    static func removeAll() { cache.removeAllObjects() }

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
