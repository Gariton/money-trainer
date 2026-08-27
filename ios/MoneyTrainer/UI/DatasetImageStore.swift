import Observation
import SwiftUI

/// Dataset画像はBearer tokenが必要なため `AsyncImage` では読めない。
/// 認証つきで取得し、メモリ上にキャッシュして一覧のスクロールに耐えるようにする。
@MainActor
@Observable
final class DatasetImageStore {
    @ObservationIgnored private let service: any DatasetServiceProtocol
    @ObservationIgnored private let cache = NSCache<NSString, UIImage>()
    @ObservationIgnored private var inFlight: [String: Task<UIImage?, Never>] = [:]

    init(service: any DatasetServiceProtocol, countLimit: Int = 240) {
        self.service = service
        cache.countLimit = countLimit
    }

    func cachedImage(id: String) -> UIImage? {
        cache.object(forKey: id as NSString)
    }

    func image(id: String) async -> UIImage? {
        if let cached = cachedImage(id: id) { return cached }
        if let existing = inFlight[id] { return await existing.value }

        let task = Task<UIImage?, Never> { [service] in
            guard let data = try? await service.imageData(id: id) else { return nil }
            return UIImage(data: data)
        }
        inFlight[id] = task
        let image = await task.value
        inFlight[id] = nil
        if let image {
            cache.setObject(image, forKey: id as NSString)
        }
        return image
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

/// Dataset画像のサムネイル。読み込み中は塗りのプレースホルダを出す。
struct DatasetImageThumbnail: View {
    let imageID: String
    var contentMode: ContentMode = .fill

    @Environment(DatasetImageStore.self) private var store
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .task(id: imageID) {
            if let cached = store.cachedImage(id: imageID) {
                image = cached
                return
            }
            let loaded = await store.image(id: imageID)
            withAnimation(.easeOut(duration: 0.15)) { image = loaded }
        }
        .accessibilityHidden(true)
    }
}
