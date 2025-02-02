import Foundation
import UIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import Display

public struct SecureIdLocalImageResourceId: MediaResourceId {
    public let id: Int64
    
    public var uniqueId: String {
        return "secure-id-local-\(self.id)"
    }
    
    public var hashValue: Int {
        return self.id.hashValue
    }
    
    public func isEqual(to: MediaResourceId) -> Bool {
        if let to = to as? SecureIdLocalImageResourceId {
            return self.id == to.id
        } else {
            return false
        }
    }
}

public class SecureIdLocalImageResource: TelegramMediaResource {
    public let localId: Int64
    public let source: TelegramMediaResource
    
    public init(localId: Int64, source: TelegramMediaResource) {
        self.localId = localId
        self.source = source
    }
    
    public required init(decoder: PostboxDecoder) {
        self.localId = decoder.decodeInt64ForKey("i", orElse: 0)
        self.source = decoder.decodeObjectForKey("s") as! TelegramMediaResource
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt64(self.localId, forKey: "i")
        encoder.encodeObject(self.source, forKey: "s")
    }
    
    public var id: MediaResourceId {
        return SecureIdLocalImageResourceId(id: self.localId)
    }
    
    public func isEqual(to: MediaResource) -> Bool {
        if let to = to as? SecureIdLocalImageResource {
            return self.localId == to.localId && self.source.isEqual(to:to.source)
        } else {
            return false
        }
    }
}

private final class Buffer {
    var data = Data()
}

func fetchSecureIdLocalImageResource(postbox: Postbox, resource: SecureIdLocalImageResource) -> Signal<MediaResourceDataFetchResult, MediaResourceDataFetchError> {
    return Signal { subscriber in
        guard let fetchResource = postbox.mediaBox.fetchResource else {
            return EmptyDisposable
        }
        
        subscriber.putNext(.reset)
        
        let fetch = fetchResource(resource.source, .single([(0 ..< Int.max, .default)]), nil)
        let buffer = Atomic<Buffer>(value: Buffer())
        let disposable = fetch.start(next: { result in
            switch result {
                case .reset:
                    let _ = buffer.with { buffer in
                        buffer.data.count = 0
                    }
                case .resourceSizeUpdated:
                    break
                case .progressUpdated:
                    break
                case let .moveLocalFile(path):
                    if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                        let _ = buffer.with { buffer in
                            buffer.data = data
                        }
                        let _ = try? FileManager.default.removeItem(atPath: path)
                    }
                case let .moveTempFile(file):
                    if let data = try? Data(contentsOf: URL(fileURLWithPath: file.path)) {
                        let _ = buffer.with { buffer in
                            buffer.data = data
                        }
                    }
                    TempBox.shared.dispose(file)
                case .copyLocalItem:
                    assertionFailure()
                    break
                case let .replaceHeader(data, range):
                    let _ = buffer.with { buffer in
                        if buffer.data.count < range.count {
                            buffer.data.count = range.count
                        }
                        buffer.data.withUnsafeMutableBytes { (bytes: UnsafeMutablePointer<UInt8>) -> Void in
                            data.copyBytes(to: bytes, from: range)
                        }
                    }
                case let .dataPart(resourceOffset, data, range, _):
                    let _ = buffer.with { buffer in
                        if buffer.data.count < resourceOffset + range.count {
                            buffer.data.count = resourceOffset + range.count
                        }
                        buffer.data.withUnsafeMutableBytes { (bytes: UnsafeMutablePointer<UInt8>) -> Void in
                            data.copyBytes(to: bytes.advanced(by: resourceOffset), from: range)
                        }
                    }
            }
        }, completed: {
            let image = buffer.with { buffer -> UIImage? in
                return UIImage(data: buffer.data)
            }
            if let image = image {
                if let scaledImage = generateImage(image.size.fitted(CGSize(width: 2048.0, height: 2048.0)), contextGenerator: { size, context in
                    context.setBlendMode(.copy)
                    context.draw(image.cgImage!, in: CGRect(origin: CGPoint(), size: size))
                }, scale: 1.0), let scaledData = UIImageJPEGRepresentation(scaledImage, 0.6) {
                    subscriber.putNext(.dataPart(resourceOffset: 0, data: scaledData, range: 0 ..< scaledData.count, complete: true))
                    subscriber.putCompletion()
                }
            }
        })
        
        return ActionDisposable {
            disposable.dispose()
        }
    }
}
