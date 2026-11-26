import CommonCrypto
import CryptoKit
import Foundation

func hmacSHA256(_ key: Data, _ message: Data) -> Data {
    Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key)))
}

/// Session keys from the AuthKey and both nonces (Gadgetbridge computeAuthStep3Hmac, AstroBox kdf_miwear):
/// HKDF-like expansion with "miwear-auth": decKey | encKey | decNonce | encNonce. The decryption nonce is
/// unused: band → phone traffic is AES-CTR, which needs none.
struct SessionKeys {
    let decKey, encKey, encNonce: Data

    init(authKey: Data, phoneNonce: Data, watchNonce: Data) {
        let prk = hmacSHA256(phoneNonce + watchNonce, authKey)
        var okm = Data(), t = Data()
        for i: UInt8 in 1...2 {
            t = hmacSHA256(prk, t + Data("miwear-auth".utf8) + [i])
            okm += t
        }
        let b = [UInt8](okm)
        decKey = Data(b[0..<16])
        encKey = Data(b[16..<32])
        encNonce = Data(b[36..<40])
    }
}

/// One AES-128 block (ECB) — the primitive CTR and CCM are built on.
func aesBlock(_ key: Data, _ block: [UInt8]) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: 16)
    var moved = 0
    let status = key.withUnsafeBytes { k in
        CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                k.baseAddress, 16, nil, block, 16, &out, 16, &moved)
    }
    precondition(status == kCCSuccess && moved == 16, "AES failed: \(status)")
    return out
}

/// AES-128-CTR with a 128-bit big-endian counter. Encrypts and decrypts.
func aesCTR(key: Data, iv: Data, _ data: Data) -> Data {
    var counter = [UInt8](iv), out = [UInt8](data)
    for start in stride(from: 0, to: out.count, by: 16) {
        let ks = aesBlock(key, counter)
        for i in start..<min(start + 16, out.count) { out[i] ^= ks[i - start] }
        for i in (0..<16).reversed() {
            counter[i] &+= 1
            if counter[i] != 0 { break }
        }
    }
    return Data(out)
}

/// AES-128-CCM encryption, no associated data, 12-byte nonce (so 3-byte length field), 4-byte tag.
/// CryptoKit has no CCM; this is RFC 3610 written out for exactly these parameters.
func aesCCMEncrypt(key: Data, nonce: Data, _ plaintext: Data) -> Data {
    precondition(nonce.count == 12 && plaintext.count < 1 << 24)
    let p = [UInt8](plaintext), n = [UInt8](nonce), tagLength = 4
    let len = [UInt8((p.count >> 16) & 0xFF), UInt8((p.count >> 8) & 0xFF), UInt8(p.count & 0xFF)]
    // B0 flags 0x0a: no Adata, M' = (4-2)/2 = 1 in bits 3-5, L' = 3-1 = 2.
    var mac = aesBlock(key, [0x0A] + n + len)
    for start in stride(from: 0, to: p.count, by: 16) {
        var block = [UInt8](repeating: 0, count: 16)
        for i in start..<min(start + 16, p.count) { block[i - start] = p[i] }
        mac = aesBlock(key, zip(mac, block).map(^))
    }
    let a = { (i: Int) -> [UInt8] in [2] + n + [UInt8(i >> 16 & 0xFF), UInt8(i >> 8 & 0xFF), UInt8(i & 0xFF)] }
    var c = p
    for (blockIndex, start) in stride(from: 0, to: p.count, by: 16).enumerated() {
        let s = aesBlock(key, a(blockIndex + 1))
        for i in start..<min(start + 16, p.count) { c[i] ^= s[i - start] }
    }
    let s0 = aesBlock(key, a(0))
    return Data(c) + Data(zip(mac.prefix(tagLength), s0).map(^))
}
