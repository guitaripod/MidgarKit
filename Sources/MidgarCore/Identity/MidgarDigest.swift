import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// SHA-256 for App Attest client data hashes: CryptoKit where it exists, ``PortableSHA256`` elsewhere.
enum MidgarDigest {
    static func sha256(_ data: Data) -> Data {
        #if canImport(CryptoKit)
        return Data(SHA256.hash(data: data))
        #else
        return PortableSHA256.hash(data)
        #endif
    }

    static func sha256(utf8 text: String) -> Data {
        sha256(Data(text.utf8))
    }

    /// The lowercase hex SHA-256 of the UTF-8 text, the form Sign in with Apple takes as a nonce.
    static func sha256Hex(utf8 text: String) -> String {
        sha256(utf8: text).map { String(format: "%02x", $0) }.joined()
    }
}

/// FIPS 180-4 SHA-256 in plain Swift, for platforms without CryptoKit. Always compiled so the tests can check it against CryptoKit and the published vectors.
enum PortableSHA256 {
    private static let roundConstants: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    static func hash(_ data: Data) -> Data {
        var state: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
        ]
        let message = padded(data)
        for offset in stride(from: 0, to: message.count, by: 64) {
            compress(&state, block: message[offset..<offset + 64])
        }
        var digest = Data()
        for word in state {
            for shift in stride(from: 24, through: 0, by: -8) {
                digest.append(UInt8(truncatingIfNeeded: word >> UInt32(shift)))
            }
        }
        return digest
    }

    /// The message, a one bit, zeros up to 56 mod 64 and the 64-bit big-endian bit length.
    private static func padded(_ data: Data) -> [UInt8] {
        var message = [UInt8](data)
        let bitLength = UInt64(message.count) &* 8
        message.append(0x80)
        while message.count % 64 != 56 {
            message.append(0)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift)))
        }
        return message
    }

    /// The 64-word message schedule of one block.
    private static func schedule(_ block: ArraySlice<UInt8>) -> [UInt32] {
        var words = [UInt32](repeating: 0, count: 64)
        let base = block.startIndex
        for index in 0..<16 {
            let offset = base + index * 4
            words[index] = UInt32(block[offset]) << 24 | UInt32(block[offset + 1]) << 16
                | UInt32(block[offset + 2]) << 8 | UInt32(block[offset + 3])
        }
        for index in 16..<64 {
            let early = words[index - 15]
            let late = words[index - 2]
            let sigma0 = rotateRight(early, 7) ^ rotateRight(early, 18) ^ (early >> 3)
            let sigma1 = rotateRight(late, 17) ^ rotateRight(late, 19) ^ (late >> 10)
            words[index] = words[index - 16] &+ sigma0 &+ words[index - 7] &+ sigma1
        }
        return words
    }

    private static func compress(_ state: inout [UInt32], block: ArraySlice<UInt8>) {
        let words = schedule(block)
        var (a, b, c, d, e, f, g, h) = (state[0], state[1], state[2], state[3], state[4], state[5], state[6], state[7])
        for round in 0..<64 {
            let sum1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25)
            let choice = (e & f) ^ (~e & g)
            let first = h &+ sum1 &+ choice &+ roundConstants[round] &+ words[round]
            let sum0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22)
            let majority = (a & b) ^ (a & c) ^ (b & c)
            let second = sum0 &+ majority
            h = g
            g = f
            f = e
            e = d &+ first
            d = c
            c = b
            b = a
            a = first &+ second
        }
        for (index, value) in [a, b, c, d, e, f, g, h].enumerated() {
            state[index] = state[index] &+ value
        }
    }

    private static func rotateRight(_ value: UInt32, _ count: UInt32) -> UInt32 {
        (value >> count) | (value << (32 - count))
    }
}
