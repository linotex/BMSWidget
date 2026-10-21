#!/usr/bin/env python3
"""Reference port of App/JBDProtocol.swift (framing, checksum, parsing) with self-tests."""


def request(cmd: int) -> bytes:
    chk = (0x10000 - cmd) & 0xFFFF
    return bytes([0xDD, 0xA5, cmd, 0x00, chk >> 8, chk & 0xFF, 0x77])


def checksum(status: int, payload: bytes) -> int:
    return (0x10000 - (status + len(payload) + sum(payload))) & 0xFFFF


def build_response(cmd: int, payload: bytes, status: int = 0) -> bytes:
    chk = checksum(status, payload)
    return bytes([0xDD, cmd, status, len(payload)]) + payload + bytes([chk >> 8, chk & 0xFF, 0x77])


class Assembler:
    def __init__(self):
        self.buf = bytearray()

    def feed(self, chunk: bytes):
        self.buf += chunk
        frames = []
        while True:
            try:
                start = self.buf.index(0xDD)
            except ValueError:
                self.buf.clear()
                break
            del self.buf[:start]
            if len(self.buf) < 4:
                break
            total = self.buf[3] + 7
            if len(self.buf) < total:
                break
            if self.buf[total - 1] == 0x77:
                frames.append(bytes(self.buf[:total]))
                del self.buf[:total]
            else:
                del self.buf[:1]
        return frames


def decode(frame: bytes):
    if len(frame) < 7 or frame[0] != 0xDD or frame[-1] != 0x77 or len(frame) != frame[3] + 7:
        raise ValueError("bad frame")
    n = frame[3]
    expected = (0x10000 - sum(frame[2:4 + n])) & 0xFFFF
    actual = (frame[4 + n] << 8) | frame[5 + n]
    if expected != actual:
        raise ValueError("checksum")
    return frame[1], frame[2], frame[4:4 + n]


def u16(p, i):
    return (p[i] << 8) | p[i + 1]


def i16(p, i):
    v = u16(p, i)
    return v - 0x10000 if v & 0x8000 else v


def basic_info(p: bytes) -> dict:
    if len(p) < 23:
        raise ValueError("too short")
    temps = [(u16(p, 23 + 2 * n) - 2731) / 10 for n in range(p[22]) if 24 + 2 * n < len(p)]
    return dict(
        voltage=u16(p, 0) / 100, current=i16(p, 2) / 100,
        remaining=u16(p, 4) / 100, nominal=u16(p, 6) / 100,
        cycles=u16(p, 8), protection=u16(p, 16), percent=p[19],
        charge_fet=bool(p[20] & 1), discharge_fet=bool(p[20] & 2),
        cells=p[21], temps=temps,
    )


def cell_voltages(p: bytes):
    return [u16(p, i) / 1000 for i in range(0, len(p) - 1, 2)]


def make_basic_payload(volt_10mv, cur_10ma, rem, nom, cycles, prot, pct, fet, cells, temps_dk):
    p = bytearray()
    for v in (volt_10mv, cur_10ma & 0xFFFF, rem, nom, cycles, 0x2078, 0, 0, prot):
        p += v.to_bytes(2, "big")
    p += bytes([0x10, pct, fet, cells, len(temps_dk)])
    for t in temps_dk:
        p += t.to_bytes(2, "big")
    return bytes(p)


def main():
    # 1. Requests
    assert request(0x03) == bytes.fromhex("DDA50300FFFD77"), request(0x03).hex()
    assert request(0x04) == bytes.fromhex("DDA50400FFFC77"), request(0x04).hex()

    # 2. Round-trip with 20-byte BLE chunking and leading garbage
    payload = make_basic_payload(5240, -820, 1450, 2000, 42, 0, 72, 0b11, 14, [2976, 2982])
    frame = build_response(0x03, payload)
    stream = b"\x00\x12" + frame
    asm = Assembler()
    got = []
    for i in range(0, len(stream), 20):
        got += asm.feed(stream[i:i + 20])
    assert got == [frame], "assembler should yield exactly the one frame"

    cmd, status, pl = decode(got[0])
    assert (cmd, status) == (0x03, 0)
    info = basic_info(pl)
    assert info["voltage"] == 52.40 and info["current"] == -8.20, info
    assert info["remaining"] == 14.50 and info["nominal"] == 20.00
    assert info["percent"] == 72 and info["cycles"] == 42 and info["cells"] == 14
    assert info["charge_fet"] and info["discharge_fet"]
    assert info["temps"] == [24.5, 25.1], info["temps"]

    # 3. Corruption is rejected
    bad = bytearray(frame)
    bad[6] ^= 0xFF
    try:
        decode(bytes(bad))
        raise AssertionError("corrupted frame accepted")
    except ValueError:
        pass

    # 4. Cell voltages, two frames back to back in one chunk
    cells_frame = build_response(0x04, b"".join(v.to_bytes(2, "big") for v in (3741, 3747, 3744)))
    two = Assembler().feed(frame + cells_frame)
    assert len(two) == 2 and cell_voltages(decode(two[1])[2]) == [3.741, 3.747, 3.744]

    # 5. Informational: a frame recalled from memory of the JBD protocol doc (not asserted).
    recalled = bytes.fromhex(
        "DD03001B17000000" "02D003E800002078" "0000000000001048"
        "030F020B760B82FB" "FF77"
    )
    try:
        c, s, p = decode(recalled)
        print("recalled sample: checksum OK ->", basic_info(p))
    except ValueError as e:
        print("recalled sample: not valid (", e, ") — my recollection of the bytes is off, ignore")

    print("OK: all assertions passed")


if __name__ == "__main__":
    main()
