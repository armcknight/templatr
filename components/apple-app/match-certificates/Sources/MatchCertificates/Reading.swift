import Foundation
import Tagged
import Security

/// A certificate's expiry and common name.
func readCertificate(_ data: Data) -> (expires: Date, name: String?)? {
    guard let certificate = SecCertificateCreateWithData(nil, data as CFData),
          let values = SecCertificateCopyValues(certificate, [kSecOIDX509V1ValidityNotAfter] as CFArray, nil) as? [CFString: Any],
          let notAfter = values[kSecOIDX509V1ValidityNotAfter] as? [CFString: Any],
          let seconds = notAfter[kSecPropertyKeyValue] as? NSNumber
    else { return nil }
    var commonName: CFString?
    SecCertificateCopyCommonName(certificate, &commonName)
    return (Date(timeIntervalSinceReferenceDate: seconds.doubleValue), commonName as String?)
}

/// A profile's property list, the content of its CMS message. As fastlane
/// reads a profile, the signature is not what this checks.
func readProfile(_ data: Data) -> [String: Any]? {
    var decoder: CMSDecoder?
    guard CMSDecoderCreate(&decoder) == errSecSuccess, let decoder else { return nil }
    let status = data.withUnsafeBytes { bytes in
        CMSDecoderUpdateMessage(decoder, bytes.baseAddress!, data.count)
    }
    var content: CFData?
    guard status == errSecSuccess,
          CMSDecoderFinalizeMessage(decoder) == errSecSuccess,
          CMSDecoderCopyContent(decoder, &content) == errSecSuccess,
          let content
    else { return nil }
    return (try? PropertyListSerialization.propertyList(from: content as Data, format: nil)) as? [String: Any]
}

/// The bundle ID a profile is for. The application identifier is the team ID,
/// a dot, and the bundle ID.
func bundleID(of profile: [String: Any]) -> BundleID {
    let entitlements = profile["Entitlements"] as? [String: Any]
    let applicationIdentifier = entitlements?["application-identifier"] as? String ?? ""
    return BundleID(applicationIdentifier.split(separator: ".", maxSplits: 1).last.map(String.init) ?? "")
}
