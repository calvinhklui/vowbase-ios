import CryptoKit
import SwiftUI
import UIKit

struct VowbaseVenueImage: View {
    let url: URL?
    var cacheKey: String? = nil
    var placeholderSystemImage: String = "building.2"

    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(
                            width: proxy.size.width,
                            height: proxy.size.height,
                            alignment: .leading
                        )
                        .clipped()
                } else {
                    venueImagePlaceholder
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .task(id: loadID) {
            image = nil
            guard let url else { return }
            let key = cacheKey ?? Self.cacheKey(for: url)
            guard let data = await VenueImageDataCache.shared.data(for: url, key: key),
                  !Task.isCancelled else { return }
            image = UIImage(data: data)
        }
        .accessibilityHidden(true)
    }

    private var loadID: String {
        "\(cacheKey ?? "")|\(url?.absoluteString ?? "")"
    }

    /// Signed Google Places and Supabase URLs can change their query string on every
    /// launch. Excluding it gives the underlying photo a durable on-disk identity.
    private static func cacheKey(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString ?? url.absoluteString
    }

    private var venueImagePlaceholder: some View {
        Image(systemName: placeholderSystemImage)
            .font(.system(size: 36, weight: .light))
            .foregroundStyle(VowbaseTheme.rose.opacity(0.65))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(VowbaseTheme.blush)
    }
}

private actor VenueImageDataCache {
    static let shared = VenueImageDataCache()

    private let directory: URL
    private let maximumAge: TimeInterval = 60 * 60 * 24 * 30
    private let maximumBytes = 100 * 1_024 * 1_024

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("VenueImages", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    func data(for url: URL, key: String) async -> Data? {
        let fileURL = directory.appendingPathComponent(Self.filename(for: key))
        if let cached = freshData(at: fileURL) {
            return cached
        }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode) else {
                return nil
            }
            try data.write(to: fileURL, options: .atomic)
            trimIfNeeded()
            return data
        } catch {
            return nil
        }
    }

    private func freshData(at fileURL: URL) -> Data? {
        guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
              let modified = values.contentModificationDate,
              Date().timeIntervalSince(modified) < maximumAge else {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        return try? Data(contentsOf: fileURL)
    }

    private func trimIfNeeded() {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: .skipsHiddenFiles
        ) else { return }

        let entries = files.compactMap { url -> (URL, Date, Int)? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return (url, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0)
        }
        var total = entries.reduce(0) { $0 + $1.2 }
        guard total > maximumBytes else { return }
        for entry in entries.sorted(by: { $0.1 < $1.1 }) where total > maximumBytes {
            try? FileManager.default.removeItem(at: entry.0)
            total -= entry.2
        }
    }

    private static func filename(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
