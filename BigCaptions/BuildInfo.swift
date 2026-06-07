import Foundation

struct BuildInfo {
    // This value is injected by the CI. 
    // If you see a compiler warning, it means the hash hasn't been set.
    static let gitHash = "unknown"
    
    static func verify() {
        if gitHash == "unknown" {
            #if !DEBUG
            // In release builds, we want to know if the hash is missing
            print("WARNING: Git Hash is unknown")
            #endif
        }
    }
}

#if DEBUG
// This will show up in your Xcode issue navigator if you forget to set it
#warning("Git Hash is currently set to 'unknown'. CI will overwrite this, but local builds may show 'unknown'.")
#endif
