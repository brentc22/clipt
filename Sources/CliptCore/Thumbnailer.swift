import Foundation
import ImageIO
import UniformTypeIdentifiers

/// An image's size in pixels, as displayed (EXIF rotation applied).
public struct PixelSize: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public enum Thumbnailer {
    /// PNG of at most `maxPixel` on the longest side, or nil if the data isn't an image.
    public static func png(from imageData: Data, maxPixel: Int = 256) -> Data? {
        guard let src = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, thumb, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// The original's pixel size, read from the header without decoding the image.
    public static func pixelSize(of imageData: Data) -> PixelSize? {
        CGImageSourceCreateWithData(imageData as CFData, nil).flatMap(pixelSize)
    }

    /// Same, for an image file: only its header is read.
    public static func pixelSize(at url: URL) -> PixelSize? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap(pixelSize)
    }

    private static func pixelSize(_ src: CGImageSource) -> PixelSize? {
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, opts) as? [CFString: Any],
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              w > 0, h > 0 else { return nil }
        // Orientations 5…8 turn the image a quarter, so width and height trade places.
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (5...8).contains(orientation) ? PixelSize(width: h, height: w) : PixelSize(width: w, height: h)
    }
}
