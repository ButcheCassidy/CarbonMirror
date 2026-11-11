import CMCoreBridge
import Foundation
import Testing

/// Loads a shared vector file from `tests/vectors/` (the same files `cargo test` runs).
func loadVectors(_ name: String) throws -> [String: Any] {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("tests/vectors/\(name)"))
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func outcome(_ body: () throws(CoreStatus) -> Void) -> String {
    do {
        try body()
        return "Ok"
    } catch {
        return error.name
    }
}

private func number(_ v: Any?) -> Double {
    if let s = v as? String, s == "NaN" { return .nan }
    return (v as? NSNumber)?.doubleValue ?? .nan
}

private func insets(_ v: Any?) -> CoreInsets {
    let a = (v as? [Any] ?? []).map(number)
    return CoreInsets(top: a[0], left: a[1], bottom: a[2], right: a[3])
}

private func rows(_ dict: [String: Any], _ key: String) -> [[String: Any]] {
    dict[key] as? [[String: Any]] ?? []
}

@Suite("Shared vectors through the C ABI")
struct VectorTests {
    @Test func abiVersionMatches() {
        #expect(CarbonCore.abiMatches)
    }

    @Test func netVectors() throws {
        let v = try loadVectors("net.json")
        #expect(!rows(v, "ip").isEmpty)
        for c in rows(v, "ip") {
            let ip = c["ip"] as? String ?? ""
            #expect(outcome { () throws(CoreStatus) in try NetPolicy.checkIP(ip) } == c["expect"] as? String, "ip \(ip)")
        }
        for c in rows(v, "endpoint") {
            let ip = c["ip"] as? String ?? ""
            let port = UInt32(number(c["port"]))
            #expect(outcome { () throws(CoreStatus) in try NetPolicy.checkEndpoint(ip: ip, port: port) } == c["expect"] as? String, "\(ip):\(port)")
        }
        for c in rows(v, "interface") {
            let name = c["name"] as? String ?? ""
            #expect(outcome { () throws(CoreStatus) in try NetPolicy.checkInterface(name) } == c["expect"] as? String, "iface \(name)")
        }
    }

    @Test func adbVectors() throws {
        let cases = rows(try loadVectors("adb.json"), "cases")
        #expect(cases.count > 40)
        for c in cases {
            let argv = c["argv"] as? [String] ?? []
            let flags = c["flags"] as? [String] ?? []
            let got = outcome { () throws(CoreStatus) in
                try AdbPolicy.validate(argv, usb: flags.contains("usb"), confirmed: flags.contains("confirmed"))
            }
            #expect(got == c["expect"] as? String, "argv \(argv)")
        }
    }

    @Test func sizeVectors() throws {
        let v = try loadVectors("size.json")
        let tol = number(v["tolerance"])
        for c in rows(v, "points_per_inch") {
            let pt = number(c["display_width_pt"]), mm = number(c["display_width_mm"])
            if let s = c["expect_status"] as? String {
                #expect(outcome { () throws(CoreStatus) in _ = try SizeMath.pointsPerInch(displayWidthPoints: pt, displayWidthMillimetres: mm) } == s)
            } else {
                #expect(abs(try SizeMath.pointsPerInch(displayWidthPoints: pt, displayWidthMillimetres: mm) - number(c["expect"])) <= 0.01)
            }
        }
        for c in rows(v, "real_size") {
            let px = CoreSize(width: number(c["phone_w_px"]), height: number(c["phone_h_px"]))
            let ppi = number(c["phone_ppi"]), ptpi = number(c["mac_pt_per_inch"])
            if let s = c["expect_status"] as? String {
                #expect(outcome { () throws(CoreStatus) in _ = try SizeMath.realSize(phonePixels: px, phonePPI: ppi, macPointsPerInch: ptpi) } == s)
            } else {
                let r = try SizeMath.realSize(phonePixels: px, phonePPI: ppi, macPointsPerInch: ptpi)
                #expect(abs(r.width - number(c["expect_w"])) <= tol && abs(r.height - number(c["expect_h"])) <= tol)
            }
        }
        for c in rows(v, "clamp") {
            let name = c["name"] as? String ?? ""
            let real = CoreSize(width: number(c["real_w"]), height: number(c["real_h"]))
            let vis = CoreSize(width: number(c["visible_w"]), height: number(c["visible_h"]))
            let scale = number(c["scale"])
            let ins = insets(c["insets"])
            if let s = c["expect_status"] as? String {
                #expect(outcome { () throws(CoreStatus) in _ = try SizeMath.clamp(real: real, scale: scale, insets: ins, visible: vis) } == s, "\(name)")
            } else {
                let r = try SizeMath.clamp(real: real, scale: scale, insets: ins, visible: vis)
                #expect(abs(r.size.width - number(c["expect_w"])) <= tol, "\(name)")
                #expect(abs(r.size.height - number(c["expect_h"])) <= tol, "\(name)")
                #expect(abs(r.scale - number(c["expect_scale"])) <= 0.001, "\(name)")
            }
        }
        for c in rows(v, "locked_resize") {
            let r = try SizeMath.lockedResize(
                currentScreen: CoreSize(width: number(c["cur_w"]), height: number(c["cur_h"])),
                proposedFrame: CoreSize(width: number(c["proposed_w"]), height: number(c["proposed_h"])),
                insets: insets(c["insets"]),
                real: CoreSize(width: number(c["real_w"]), height: number(c["real_h"])),
                visible: CoreSize(width: number(c["visible_w"]), height: number(c["visible_h"])))
            #expect(abs(r.width - number(c["expect_w"])) <= tol && abs(r.height - number(c["expect_h"])) <= tol, "\(c["name"] ?? "")")
        }
        for c in rows(v, "corner_radius") {
            let w = number(c["window_w"]), d = number(c["device_radius_px"]), p = number(c["phone_w_px"]), f = number(c["fine_tune"])
            let device: Double? = d > 0 ? d : nil
            if let s = c["expect_status"] as? String {
                #expect(outcome { () throws(CoreStatus) in _ = try SizeMath.cornerRadius(windowWidth: w, deviceRadiusPixels: device, phoneWidthPixels: p, fineTune: f) } == s)
            } else {
                #expect(abs(try SizeMath.cornerRadius(windowWidth: w, deviceRadiusPixels: device, phoneWidthPixels: p, fineTune: f) - number(c["expect"])) <= 0.01)
            }
        }
    }

    @Test func failureVectors() throws {
        let v = try loadVectors("failure.json")
        for c in rows(v, "cases") {
            let name = c["failure"] as? String ?? ""
            let failure = try #require(FailureClass.allCases.first { String(describing: $0).lowercased() == name.lowercased() }, "\(name)")
            let state = try FailureMap.uiState(for: failure, attempt: UInt32(number(c["attempt"])))
            #expect(String(describing: state).lowercased() == (c["expect"] as? String ?? "").lowercased(), "\(name)")
        }
    }

    @Test func deviceListVectors() throws {
        let v = try loadVectors("adb_devices.json")
        for c in rows(v, "cases") {
            let bytes: [UInt8]
            if let hex = c["input_hex"] as? String {
                bytes = stride(from: 0, to: hex.count, by: 2).map { i in
                    let s = hex.index(hex.startIndex, offsetBy: i)
                    return UInt8(hex[s..<hex.index(s, offsetBy: 2)], radix: 16) ?? 0
                }
            } else {
                bytes = Array((c["input"] as? String ?? "").utf8)
            }
            if let s = c["expect_status"] as? String {
                #expect(outcome { () throws(CoreStatus) in _ = try AdbDeviceList.parse(bytes) } == s)
            } else {
                let got = try AdbDeviceList.parse(bytes).map { "\($0.serial)\t\($0.state)\t\($0.model)\t\($0.transportID)\t\($0.link.rawValue)" }
                #expect(got == c["expect"] as? [String] ?? [], "\(c["name"] ?? "")")
            }
        }
        for c in rows(v, "track_frames") {
            let bytes = Array((c["input"] as? String ?? "").utf8)
            switch c["expect_status"] as? String {
            case "NeedMoreData"?:
                #expect(try AdbDeviceList.trackFrame(bytes) == nil)
            case let s?:
                #expect(outcome { () throws(CoreStatus) in _ = try AdbDeviceList.trackFrame(bytes) } == s)
            case nil:
                let off = Int(number(c["expect_offset"])), len = Int(number(c["expect_len"]))
                #expect(try AdbDeviceList.trackFrame(bytes) == off..<(off + len))
            }
        }
        let big = [UInt8](repeating: UInt8(ascii: "a"), count: Int(number(v["too_large_bytes"])))
        #expect(outcome { () throws(CoreStatus) in _ = try AdbDeviceList.parse(big) } == "ParseTooLarge")
    }
}
