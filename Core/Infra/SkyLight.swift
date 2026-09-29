import Foundation

enum SkyLight {
    private static let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"

    /// The handle stays open, since closing it can unload the framework the pointer belongs to.
    static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle = dlopen(path, RTLD_LAZY),
              let address = dlsym(handle, name) else { return nil }

        return unsafeBitCast(address, to: type)
    }
}
