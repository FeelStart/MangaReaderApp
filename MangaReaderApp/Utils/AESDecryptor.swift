import Foundation
import CommonCrypto

/// AES decryption utility for COPY manga source
/// Implements the same algorithm as CryptoJS in the original TypeScript implementation
public struct AESDecryptor {
    /// Decrypt content using AES-CBC with PKCS7 padding
    /// - Parameters:
    ///   - contentKey: Encrypted content (IV + encrypted data in hex)
    ///   - key: Decryption key
    /// - Returns: Decrypted string
    /// - Throws: DecryptionError if decryption fails
    public static func decrypt(contentKey: String, key: String) throws -> String {
        // Extract IV (first 16 characters)
        let ivString = String(contentKey.prefix(16))

        // Extract encrypted content (after first 16 characters)
        let encryptedHex = String(contentKey.dropFirst(16))

        // Convert key to Data
        guard let keyData = key.data(using: .utf8) else {
            throw DecryptionError.invalidKey
        }

        // Convert IV to Data
        guard let ivData = ivString.data(using: .utf8) else {
            throw DecryptionError.invalidIV
        }

        // Convert hex string to Data
        guard let encryptedData = Data(hexString: encryptedHex) else {
            throw DecryptionError.invalidEncryptedData
        }

        // Perform AES-CBC decryption
        let decryptedData = try aesDecrypt(
            data: encryptedData,
            key: keyData,
            iv: ivData
        )

        // Convert decrypted data to string
        guard let decryptedString = String(data: decryptedData, encoding: .utf8) else {
            throw DecryptionError.invalidDecryptedData
        }

        return decryptedString
    }

    /// Perform AES-128-CBC decryption using CommonCrypto
    private static func aesDecrypt(data: Data, key: Data, iv: Data) throws -> Data {
        // Ensure key is 16 bytes (AES-128)
        var keyBytes = [UInt8](repeating: 0, count: kCCKeySizeAES128)
        key.copyBytes(to: &keyBytes, count: min(key.count, kCCKeySizeAES128))

        // Ensure IV is 16 bytes
        var ivBytes = [UInt8](repeating: 0, count: kCCBlockSizeAES128)
        iv.copyBytes(to: &ivBytes, count: min(iv.count, kCCBlockSizeAES128))

        // Prepare output buffer
        let dataLength = data.count
        let bufferSize = dataLength + kCCBlockSizeAES128
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var numBytesDecrypted = 0

        // Perform decryption
        let cryptStatus = data.withUnsafeBytes { dataBytes in
            CCCrypt(
                CCOperation(kCCDecrypt),
                CCAlgorithm(kCCAlgorithmAES),
                CCOptions(kCCOptionPKCS7Padding),
                keyBytes,
                kCCKeySizeAES128,
                ivBytes,
                dataBytes.baseAddress,
                dataLength,
                &buffer,
                bufferSize,
                &numBytesDecrypted
            )
        }

        guard cryptStatus == kCCSuccess else {
            throw DecryptionError.decryptionFailed(Int(cryptStatus))
        }

        return Data(bytes: buffer, count: numBytesDecrypted)
    }
}

// MARK: - Decryption Errors

public enum DecryptionError: LocalizedError {
    case invalidKey
    case invalidIV
    case invalidEncryptedData
    case invalidDecryptedData
    case decryptionFailed(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidKey:
            return "Invalid decryption key"
        case .invalidIV:
            return "Invalid initialization vector"
        case .invalidEncryptedData:
            return "Invalid encrypted data format"
        case .invalidDecryptedData:
            return "Decrypted data is not valid UTF-8"
        case .decryptionFailed(let status):
            return "Decryption failed with status: \(status)"
        }
    }
}

// MARK: - Data Extension for Hex Conversion

extension Data {
    /// Initialize Data from hex string
    init?(hexString: String) {
        let length = hexString.count / 2
        var data = Data(capacity: length)

        var index = hexString.startIndex
        for _ in 0..<length {
            let nextIndex = hexString.index(index, offsetBy: 2)
            let byteString = hexString[index..<nextIndex]

            guard let byte = UInt8(byteString, radix: 16) else {
                return nil
            }

            data.append(byte)
            index = nextIndex
        }

        self = data
    }
}
