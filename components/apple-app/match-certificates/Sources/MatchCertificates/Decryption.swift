import CommonCrypto
import CryptoKit
import Foundation

// fastlane's Match::Encryption::MatchDataEncryption, both versions, so that
// reading the match repository needs neither Ruby nor fastlane.

enum DecryptionError: Error {
    case malformed
    case wrongPassword
}

enum Digest {
    case md5, sha256
}

/// OpenSSL's EVP_BytesToKey with one iteration, which Ruby's
/// `Cipher#pkcs5_keyivgen` is: each block is the digest of the one before, the
/// password and the salt.
func bytesToKey(password: Data, salt: Data, digest: Digest, length: Int) -> Data {
    var result = Data()
    var block = Data()
    while result.count < length {
        let input = block + password + salt
        switch digest {
        case .md5: block = Data(Insecure.MD5.hash(data: input))
        case .sha256: block = Data(SHA256.hash(data: input))
        }
        result += block
    }
    return result.prefix(length)
}

/// Version 1: AES-256-CBC, with the key and IV from EVP_BytesToKey.
func decryptV1(_ data: Data, password: Data, salt: Data, digest: Digest) throws -> Data {
    let keyIV = bytesToKey(password: password, salt: salt, digest: digest, length: kCCKeySizeAES256 + kCCBlockSizeAES128)
    let key = keyIV.prefix(kCCKeySizeAES256)
    let iv = keyIV.suffix(kCCBlockSizeAES128)
    var output = Data(count: data.count + kCCBlockSizeAES128)
    var written = 0
    let outputCount = output.count
    let status = output.withUnsafeMutableBytes { outputBytes in
        data.withUnsafeBytes { dataBytes in
            key.withUnsafeBytes { keyBytes in
                iv.withUnsafeBytes { ivBytes in
                    CCCrypt(
                        CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                        keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                        dataBytes.baseAddress, data.count,
                        outputBytes.baseAddress, outputCount, &written
                    )
                }
            }
        }
    }
    guard status == kCCSuccess else { throw DecryptionError.wrongPassword }
    return output.prefix(written)
}

/// Version 2: AES-256-GCM, with the key, the IV and the authenticated data
/// from PBKDF2-HMAC-SHA256.
func decryptV2(_ data: Data, password: Data, salt: Data, tag: Data) throws -> Data {
    var keyIV = Data(count: 32 + 12 + 24)
    let keyIVCount = keyIV.count
    let status = keyIV.withUnsafeMutableBytes { keyIVBytes in
        salt.withUnsafeBytes { saltBytes in
            password.withUnsafeBytes { passwordBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.bindMemory(to: CChar.self).baseAddress, password.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 10_000,
                    keyIVBytes.bindMemory(to: UInt8.self).baseAddress, keyIVCount
                )
            }
        }
    }
    guard status == kCCSuccess else { throw DecryptionError.malformed }
    let key = SymmetricKey(data: keyIV.prefix(32))
    let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: keyIV.subdata(in: 32..<44)), ciphertext: data, tag: tag)
    do {
        return try AES.GCM.open(box, using: key, authenticating: keyIV.subdata(in: 44..<68))
    } catch {
        throw DecryptionError.wrongPassword
    }
}

/// Decrypts a file of the match repository: base64 of a prefix, an 8-byte salt,
/// for version 2 a 16-byte tag, and the encrypted data. It returns each data
/// that the file decrypts to, to read in turn: version 1 has no integrity
/// check, so data that decrypts with the wrong digest can be garbage.
func decrypt(_ contents: Data, password: MatchPassword) throws -> [Data] {
    guard let stored = Data(base64Encoded: contents, options: .ignoreUnknownCharacters) else { throw DecryptionError.malformed }
    let password = Data(password.rawValue.utf8)
    let v2Prefix = Data("match_encrypted_v2__".utf8)
    if stored.starts(with: v2Prefix) {
        let start = stored.startIndex + v2Prefix.count
        guard stored.count >= v2Prefix.count + 8 + 16 else { throw DecryptionError.malformed }
        let salt = stored.subdata(in: start..<start + 8)
        let tag = stored.subdata(in: start + 8..<start + 24)
        return [try decryptV2(stored.subdata(in: start + 24..<stored.endIndex), password: password, salt: salt, tag: tag)]
    }
    guard stored.count >= 16 else { throw DecryptionError.malformed }
    let salt = stored.subdata(in: stored.startIndex + 8..<stored.startIndex + 16)
    let encrypted = stored.subdata(in: stored.startIndex + 16..<stored.endIndex)
    // OpenSSL 1.0 used MD5, and 1.1 and later SHA-256; fastlane tries both.
    let candidates = [Digest.md5, .sha256].compactMap { try? decryptV1(encrypted, password: password, salt: salt, digest: $0) }
    guard !candidates.isEmpty else { throw DecryptionError.wrongPassword }
    return candidates
}
