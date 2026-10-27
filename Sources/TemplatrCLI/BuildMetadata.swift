extension TemplatrCommand {
    /// The version with semver build metadata appended when there is any, so a
    /// local build reads as e.g. `0.1.0+d0a4bc2.dirty` and a release as `0.1.0`.
    static var fullVersion: String {
        buildMetadata.map { "\(version)+\($0)" } ?? version
    }
}

// `make install` compiles with TEMPLATR_DEV_BUILD and generates
// BuildMetadata.generated.swift, which defines `buildMetadata` from the git
// hash. Every other build, including CI's, gets none.
#if !TEMPLATR_DEV_BUILD
extension TemplatrCommand {
    static let buildMetadata: String? = nil
}
#endif
