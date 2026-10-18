import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// In-memory cache for decoded artwork images to eliminate repeated decoding during scrolling.
public final class ArtworkImageCache: @unchecked Sendable {
    public static let shared = ArtworkImageCache()
    
    private let cache = NSCache<NSString, PlatformImage>()
    
    public init() {
        cache.countLimit = 150
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
    }
    
    public func image(for data: Data, id: UUID? = nil, fallbackKey: String = "") -> PlatformImage? {
        let key: NSString
        if let id = id {
            key = "\(id.uuidString)_\(data.count)" as NSString
        } else {
            var hasher = Hasher()
            hasher.combine(fallbackKey)
            hasher.combine(data.count)
            key = "\(hasher.finalize())" as NSString
        }
        
        if let cached = cache.object(forKey: key) {
            return cached
        }
        
        guard let image = PlatformImage(data: data) else {
            return nil
        }
        
        cache.setObject(image, forKey: key, cost: data.count)
        return image
    }
    
    public func removeAll() {
        cache.removeAllObjects()
    }
}

/// Renders cover art from raw data or displays an aesthetic fallback banner.
public struct ArtworkImageView: View {
    public let itemID: UUID?
    public let artworkData: Data?
    public let title: String
    public let kind: ItemKind
    public var cornerRadius: CGFloat = 8.0
    
    public init(
        itemID: UUID? = nil,
        artworkData: Data?,
        title: String,
        kind: ItemKind = .singleFile,
        cornerRadius: CGFloat = 8.0
    ) {
        self.itemID = itemID
        self.artworkData = artworkData
        self.title = title
        self.kind = kind
        self.cornerRadius = cornerRadius
    }
    
    public var body: some View {
        Group {
            if let data = artworkData,
               let platformImage = ArtworkImageCache.shared.image(for: data, id: itemID, fallbackKey: title) {
                #if canImport(UIKit)
                Image(uiImage: platformImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                #elseif canImport(AppKit)
                Image(nsImage: platformImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                #endif
            } else {
                fallbackPlaceholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
    
    private var fallbackPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: gradientColors(for: title),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(spacing: 4) {
                Image(systemName: kind.systemIconName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                
                Text(title.prefix(1).uppercased())
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(4)
        }
    }
    
    /// Deterministic, pleasant gradient pairs based on the hash of the item's title.
    private func gradientColors(for text: String) -> [Color] {
        let palettes: [[Color]] = [
            [.blue, .indigo],
            [.purple, .pink],
            [.orange, .red],
            [.teal, .blue],
            [.indigo, .cyan],
            [.mint, .teal],
            [.brown, .orange]
        ]
        let index = abs(text.hashValue) % palettes.count
        return palettes[index]
    }
}

#Preview {
    HStack(spacing: 16) {
        ArtworkImageView(artworkData: nil, title: "Jack Reacher", kind: .singleFile)
            .frame(width: 80, height: 80)
        
        ArtworkImageView(artworkData: nil, title: "Pimsleur Spanish", kind: .folder)
            .frame(width: 80, height: 80)
    }
    .padding()
}
