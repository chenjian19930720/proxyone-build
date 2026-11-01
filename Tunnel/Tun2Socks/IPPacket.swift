import Foundation

// MARK: - TCP 标志位
enum TCPFlags {
    static let fin: UInt8 = 0x01
    static let syn: UInt8 = 0x02
    static let rst: UInt8 = 0x04
    static let psh: UInt8 = 0x08
    static let ack: UInt8 = 0x10
}

// MARK: - 解析后的 IPv4 包
struct IPv4Packet {
    var srcIP: UInt32        // 网络字节序原样保存
    var dstIP: UInt32
    var proto: UInt8
    var payload: [UInt8]
    var headerLength: Int
}

struct TCPHeader {
    var srcPort: UInt16
    var dstPort: UInt16
    var seq: UInt32
    var ack: UInt32
    var flags: UInt8
    var window: UInt16
    var headerLength: Int
    var payload: [UInt8]
}

struct UDPHeader {
    var srcPort: UInt16
    var dstPort: UInt16
    var payload: [UInt8]
}

// MARK: - 解析
enum PacketParser {

    static func parseIPv4(_ bytes: [UInt8]) -> IPv4Packet? {
        guard bytes.count >= 20 else { return nil }
        let version = bytes[0] >> 4
        guard version == 4 else { return nil }
        let ihl = Int(bytes[0] & 0x0F) * 4
        guard ihl >= 20, bytes.count >= ihl else { return nil }
        let totalLength = Int(bytes[2]) << 8 | Int(bytes[3])
        guard totalLength >= ihl, bytes.count >= totalLength else { return nil }
        // 分片包：本实现不做重组，直接丢弃非首片
        let fragField = Int(bytes[6]) << 8 | Int(bytes[7])
        let moreFragments = (fragField & 0x2000) != 0
        let fragOffset = fragField & 0x1FFF
        if moreFragments || fragOffset != 0 { return nil }

        var src: UInt32 = 0, dst: UInt32 = 0
        withUnsafeMutableBytes(of: &src) { $0.copyBytes(from: bytes[12..<16]) }
        withUnsafeMutableBytes(of: &dst) { $0.copyBytes(from: bytes[16..<20]) }

        return IPv4Packet(srcIP: src, dstIP: dst, proto: bytes[9],
                          payload: Array(bytes[ihl..<totalLength]), headerLength: ihl)
    }

    static func parseTCP(_ payload: [UInt8]) -> TCPHeader? {
        guard payload.count >= 20 else { return nil }
        let offset = Int(payload[12] >> 4) * 4
        guard offset >= 20, payload.count >= offset else { return nil }
        return TCPHeader(
            srcPort: be16(payload, 0),
            dstPort: be16(payload, 2),
            seq: be32(payload, 4),
            ack: be32(payload, 8),
            flags: payload[13],
            window: be16(payload, 14),
            headerLength: offset,
            payload: Array(payload[offset...])
        )
    }

    static func parseUDP(_ payload: [UInt8]) -> UDPHeader? {
        guard payload.count >= 8 else { return nil }
        let length = Int(be16(payload, 4))
        guard length >= 8, payload.count >= length else { return nil }
        return UDPHeader(srcPort: be16(payload, 0),
                         dstPort: be16(payload, 2),
                         payload: Array(payload[8..<length]))
    }

    static func be16(_ b: [UInt8], _ i: Int) -> UInt16 {
        UInt16(b[i]) << 8 | UInt16(b[i + 1])
    }

    static func be32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) << 24 | UInt32(b[i + 1]) << 16 | UInt32(b[i + 2]) << 8 | UInt32(b[i + 3])
    }
}

// MARK: - 构造
enum PacketBuilder {

    private static var ipID: UInt16 = UInt16.random(in: 1...60000)
    private static var idLock = NSLock()

    private static func nextID() -> UInt16 {
        idLock.lock(); defer { idLock.unlock() }
        ipID &+= 1
        if ipID == 0 { ipID = 1 }
        return ipID
    }

    static func tcp(src: UInt32, dst: UInt32,
                    srcPort: UInt16, dstPort: UInt16,
                    seq: UInt32, ack: UInt32,
                    flags: UInt8, window: UInt16 = 65535,
                    payload: [UInt8] = []) -> [UInt8] {
        var tcp = [UInt8](repeating: 0, count: 20 + payload.count)
        writeBE16(&tcp, 0, srcPort)
        writeBE16(&tcp, 2, dstPort)
        writeBE32(&tcp, 4, seq)
        writeBE32(&tcp, 8, ack)
        tcp[12] = 5 << 4              // data offset = 5 (20 字节)
        tcp[13] = flags
        writeBE16(&tcp, 14, window)
        if !payload.isEmpty { tcp.replaceSubrange(20..<(20 + payload.count), with: payload) }
        // 校验和
        let csum = transportChecksum(src: src, dst: dst, proto: 6, segment: tcp)
        writeBE16(&tcp, 16, csum)
        return ipv4(src: src, dst: dst, proto: 6, payload: tcp)
    }

    static func udp(src: UInt32, dst: UInt32,
                    srcPort: UInt16, dstPort: UInt16,
                    payload: [UInt8]) -> [UInt8] {
        var udp = [UInt8](repeating: 0, count: 8 + payload.count)
        writeBE16(&udp, 0, srcPort)
        writeBE16(&udp, 2, dstPort)
        writeBE16(&udp, 4, UInt16(8 + payload.count))
        if !payload.isEmpty { udp.replaceSubrange(8..<(8 + payload.count), with: payload) }
        let csum = transportChecksum(src: src, dst: dst, proto: 17, segment: udp)
        writeBE16(&udp, 6, csum == 0 ? 0xFFFF : csum)
        return ipv4(src: src, dst: dst, proto: 17, payload: udp)
    }

    static func ipv4(src: UInt32, dst: UInt32, proto: UInt8, payload: [UInt8]) -> [UInt8] {
        var header = [UInt8](repeating: 0, count: 20)
        header[0] = 0x45
        header[1] = 0
        writeBE16(&header, 2, UInt16(20 + payload.count))
        writeBE16(&header, 4, nextID())
        writeBE16(&header, 6, 0x4000)          // DF
        header[8] = 64                          // TTL
        header[9] = proto
        withUnsafeBytes(of: src) { header.replaceSubrange(12..<16, with: $0) }
        withUnsafeBytes(of: dst) { header.replaceSubrange(16..<20, with: $0) }
        writeBE16(&header, 10, 0)
        writeBE16(&header, 10, onesComplementSum(header))
        header.append(contentsOf: payload)
        return header
    }

    // MARK: 校验和
    private static func transportChecksum(src: UInt32, dst: UInt32, proto: UInt8, segment: [UInt8]) -> UInt16 {
        var pseudo = [UInt8](repeating: 0, count: 12)
        withUnsafeBytes(of: src) { pseudo.replaceSubrange(0..<4, with: $0) }
        withUnsafeBytes(of: dst) { pseudo.replaceSubrange(4..<8, with: $0) }
        pseudo[9] = proto
        writeBE16(&pseudo, 10, UInt16(segment.count))
        var all = pseudo
        all.append(contentsOf: segment)
        if all.count % 2 == 1 { all.append(0) }
        return onesComplementSum(all)
    }

    private static func onesComplementSum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < bytes.count {
            sum &+= UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1])
            i += 2
        }
        if i < bytes.count { sum &+= UInt32(bytes[i]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xFFFF) &+ (sum >> 16) }
        return UInt16(~sum & 0xFFFF)
    }

    static func writeBE16(_ b: inout [UInt8], _ i: Int, _ v: UInt16) {
        b[i] = UInt8(v >> 8); b[i + 1] = UInt8(v & 0xFF)
    }

    static func writeBE32(_ b: inout [UInt8], _ i: Int, _ v: UInt32) {
        b[i] = UInt8(v >> 24); b[i + 1] = UInt8((v >> 16) & 0xFF)
        b[i + 2] = UInt8((v >> 8) & 0xFF); b[i + 3] = UInt8(v & 0xFF)
    }
}

// MARK: - 地址工具
enum IPUtil {
    static func stringToAddr(_ s: String) -> UInt32? {
        var addr = in_addr()
        guard inet_pton(AF_INET, s, &addr) == 1 else { return nil }
        return addr.s_addr
    }

    static func addrToString(_ a: UInt32) -> String {
        var addr = in_addr(s_addr: a)
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        buf.withUnsafeMutableBufferPointer { ptr in
            _ = withUnsafePointer(to: &addr) {
                inet_ntop(AF_INET, $0, ptr.baseAddress, socklen_t(INET_ADDRSTRLEN))
            }
        }
        return String(cString: buf)
    }

    static func isMulticast(_ a: UInt32) -> Bool {
        // 224.0.0.0/4
        let host = UInt32(bigEndian: a)
        return (host >> 28) == 0xE
    }

    static func isBroadcast(_ a: UInt32) -> Bool {
        a == 0xFFFFFFFF || a == 0
    }
}
