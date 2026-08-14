import SwiftUI

enum ImageDataNormalizer {
    static func jpegData(from data: Data, compressionQuality: Double = 0.92) throws -> Data {
        guard let image = UIImage(data: data) else {
            throw ImageNormalizationError.unsupportedImage
        }
        guard let jpegData = image.jpegData(compressionQuality: compressionQuality) else {
            throw ImageNormalizationError.encodingFailed
        }
        return jpegData
    }
}
