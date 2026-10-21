import Foundation

/// JBD / Xiaoxiang BMS wire protocol (UART over BLE, service FF00 or FFE0).
///
/// Request:  DD A5 <cmd> 00 <chk hi> <chk lo> 77
/// Response: DD <cmd> <status> <len> <payload…> <chk hi> <chk lo> 77
/// Checksum: 0x10000 - (sum of [status, len, payload…])  — for requests: 0x10000 - cmd.
enum JBDError: Error {
    case badFrame
    case checksum
    case tooShort
}

enum JBDCommand: UInt8 {
    case basicInfo = 0x03
    case cellVoltages = 0x04
}

enum JBDProtocol {
    struct Frame {
        let command: UInt8
        let status: UInt8
        let payload: [UInt8]
    }

    static func request(_ command: JBDCommand) -> Data {
        let checksum = UInt16(0) &- UInt16(command.rawValue)
        return Data([0xDD, 0xA5, command.rawValue, 0x00,
                     UInt8(checksum >> 8), UInt8(checksum & 0xFF), 0x77])
    }

    static func decode(_ bytes: [UInt8]) throws -> Frame {
        guard bytes.count >= 7, bytes[0] == 0xDD, bytes[bytes.count - 1] == 0x77 else {
            throw JBDError.badFrame
        }
        let length = Int(bytes[3])
        guard bytes.count == length + 7 else { throw JBDError.badFrame }

        let sum = bytes[2..<(4 + length)].reduce(UInt16(0)) { $0 &+ UInt16($1) }
        let expected = UInt16(0) &- sum
        let actual = UInt16(bytes[4 + length]) << 8 | UInt16(bytes[5 + length])
        guard expected == actual else { throw JBDError.checksum }

        return Frame(command: bytes[1], status: bytes[2], payload: Array(bytes[4..<(4 + length)]))
    }

    /// Payload of command 0x03.
    static func basicInfo(from p: [UInt8], at date: Date = .now) throws -> BMSSnapshot {
        guard p.count >= 23 else { throw JBDError.tooShort }

        func u16(_ i: Int) -> UInt16 { UInt16(p[i]) << 8 | UInt16(p[i + 1]) }
        func i16(_ i: Int) -> Int16 { Int16(bitPattern: u16(i)) }

        var temperatures: [Double] = []
        for n in 0..<Int(p[22]) {
            let offset = 23 + n * 2
            guard offset + 1 < p.count else { break }
            temperatures.append((Double(u16(offset)) - 2731) / 10)   // 0.1 K → °C
        }

        return BMSSnapshot(
            timestamp: date,
            voltage: Double(u16(0)) / 100,
            current: Double(i16(2)) / 100,
            remainingAh: Double(u16(4)) / 100,
            nominalAh: Double(u16(6)) / 100,
            cycles: Int(u16(8)),
            percent: Int(p[19]),
            chargeFET: p[20] & 0x01 != 0,
            dischargeFET: p[20] & 0x02 != 0,
            cellCount: Int(p[21]),
            temperatures: temperatures,
            protectionFlags: u16(16),
            cellVoltages: []
        )
    }

    /// Payload of command 0x04: N × uint16, millivolts.
    static func cellVoltages(from p: [UInt8]) -> [Double] {
        stride(from: 0, to: p.count - 1, by: 2).map {
            Double(UInt16(p[$0]) << 8 | UInt16(p[$0 + 1])) / 1000
        }
    }
}

/// BLE notifications arrive in ≤20-byte chunks; this stitches them back into frames.
struct JBDFrameAssembler {
    private var buffer: [UInt8] = []

    mutating func feed(_ chunk: Data) -> [[UInt8]] {
        buffer.append(contentsOf: chunk)
        var frames: [[UInt8]] = []

        while true {
            guard let start = buffer.firstIndex(of: 0xDD) else {
                buffer.removeAll()
                break
            }
            if start > 0 { buffer.removeFirst(start) }
            guard buffer.count >= 4 else { break }

            let total = Int(buffer[3]) + 7
            guard buffer.count >= total else { break }

            if buffer[total - 1] == 0x77 {
                frames.append(Array(buffer[0..<total]))
                buffer.removeFirst(total)
            } else {
                buffer.removeFirst()   // false start byte, resync
            }
        }
        return frames
    }

    mutating func reset() { buffer.removeAll() }
}
