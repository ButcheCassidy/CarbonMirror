//! Runs the shared test vectors in `tests/vectors/*.json` against the Rust core. The Swift suite runs the
//! same files through the C ABI; any disagreement between the two is a bug.

use carbon_core::policy::{adb, failure, net, size};
use carbon_core::protocol::adb_devices;
use carbon_core::status::CmStatus;
use serde_json::Value;

fn load(name: &str) -> Value {
    let path = format!("{}/../../tests/vectors/{name}", env!("CARGO_MANIFEST_DIR"));
    serde_json::from_str(&std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{path}: {e}"))).expect("valid JSON")
}

fn status_name(s: CmStatus) -> String {
    format!("{s:?}")
}

fn outcome<T>(r: Result<T, CmStatus>) -> String {
    r.map_or_else(status_name, |_| "Ok".to_owned())
}

fn num(v: &Value) -> f64 {
    v.as_f64().unwrap_or_else(|| if v.as_str() == Some("NaN") { f64::NAN } else { panic!("not a number: {v}") })
}

fn insets(v: &Value) -> size::CmInsets {
    let a: Vec<f64> = v.as_array().expect("insets").iter().map(num).collect();
    size::CmInsets { top: a[0], left: a[1], bottom: a[2], right: a[3] }
}

fn close(a: f64, b: f64, tol: f64, what: &str) {
    assert!((a - b).abs() <= tol, "{what}: got {a}, expected {b}");
}

#[test]
fn net_vectors() {
    let v = load("net.json");
    for c in v["ip"].as_array().unwrap() {
        assert_eq!(outcome(net::check_ip(c["ip"].as_str().unwrap())), c["expect"], "ip {}", c["ip"]);
    }
    for c in v["endpoint"].as_array().unwrap() {
        let r = net::check_endpoint(c["ip"].as_str().unwrap(), c["port"].as_u64().unwrap() as u32);
        assert_eq!(outcome(r), c["expect"], "endpoint {c}");
    }
    for c in v["interface"].as_array().unwrap() {
        assert_eq!(outcome(net::check_interface(c["name"].as_str().unwrap())), c["expect"], "iface {c}");
    }
}

#[test]
fn adb_vectors() {
    for c in load("adb.json")["cases"].as_array().unwrap() {
        let argv: Vec<&str> = c["argv"].as_array().unwrap().iter().map(|a| a.as_str().unwrap()).collect();
        let flags = c["flags"].as_array().unwrap().iter().fold(0, |f, n| match n.as_str().unwrap() {
            "usb" => f | adb::FLAG_TRANSPORT_USB,
            "confirmed" => f | adb::FLAG_USER_CONFIRMED,
            other => panic!("unknown flag {other}"),
        });
        assert_eq!(outcome(adb::validate(&argv, flags)), c["expect"], "argv {argv:?}");
    }
}

#[test]
fn size_vectors() {
    let v = load("size.json");
    let tol = v["tolerance"].as_f64().unwrap();
    for c in v["points_per_inch"].as_array().unwrap() {
        let r = size::mac_points_per_inch(num(&c["display_width_pt"]), num(&c["display_width_mm"]));
        match c.get("expect_status") {
            Some(s) => assert_eq!(outcome(r), *s),
            None => close(r.unwrap(), num(&c["expect"]), 0.01, "ppi"),
        }
    }
    for c in v["real_size"].as_array().unwrap() {
        let px = size::CmSize { w: num(&c["phone_w_px"]), h: num(&c["phone_h_px"]) };
        let r = size::real_size(px, num(&c["phone_ppi"]), num(&c["mac_pt_per_inch"]));
        match c.get("expect_status") {
            Some(s) => assert_eq!(outcome(r), *s),
            None => {
                let s = r.unwrap();
                close(s.w, num(&c["expect_w"]), tol, "real w");
                close(s.h, num(&c["expect_h"]), tol, "real h");
            }
        }
    }
    for c in v["clamp"].as_array().unwrap() {
        let real = size::CmSize { w: num(&c["real_w"]), h: num(&c["real_h"]) };
        let vis = size::CmSize { w: num(&c["visible_w"]), h: num(&c["visible_h"]) };
        let r = size::clamp_scale(real, num(&c["scale"]), insets(&c["insets"]), vis);
        match c.get("expect_status") {
            Some(s) => assert_eq!(outcome(r), *s, "{}", c["name"]),
            None => {
                let (s, scale) = r.unwrap();
                close(s.w, num(&c["expect_w"]), tol, c["name"].as_str().unwrap());
                close(s.h, num(&c["expect_h"]), tol, c["name"].as_str().unwrap());
                close(scale, num(&c["expect_scale"]), 0.001, c["name"].as_str().unwrap());
            }
        }
    }
    for c in v["locked_resize"].as_array().unwrap() {
        let r = size::locked_resize(
            size::CmSize { w: num(&c["cur_w"]), h: num(&c["cur_h"]) },
            size::CmSize { w: num(&c["proposed_w"]), h: num(&c["proposed_h"]) },
            insets(&c["insets"]),
            size::CmSize { w: num(&c["real_w"]), h: num(&c["real_h"]) },
            size::CmSize { w: num(&c["visible_w"]), h: num(&c["visible_h"]) },
        )
        .unwrap();
        close(r.w, num(&c["expect_w"]), tol, c["name"].as_str().unwrap());
        close(r.h, num(&c["expect_h"]), tol, c["name"].as_str().unwrap());
    }
    for c in v["corner_radius"].as_array().unwrap() {
        let r = size::corner_radius(
            num(&c["window_w"]),
            num(&c["device_radius_px"]),
            num(&c["phone_w_px"]),
            num(&c["fine_tune"]),
        );
        match c.get("expect_status") {
            Some(s) => assert_eq!(outcome(r), *s),
            None => close(r.unwrap(), num(&c["expect"]), 0.01, "radius"),
        }
    }
}

fn failure_by_name(name: &str) -> failure::FailureClass {
    (1..=14)
        .map(|i| failure::FailureClass::from_u32(i).unwrap())
        .find(|f| format!("{f:?}") == name)
        .unwrap_or_else(|| panic!("unknown failure {name}"))
}

#[test]
fn failure_vectors() {
    let v = load("failure.json");
    for c in v["cases"].as_array().unwrap() {
        let state = failure::ui_state(failure_by_name(c["failure"].as_str().unwrap()), c["attempt"].as_u64().unwrap() as u32);
        assert_eq!(format!("{state:?}"), c["expect"].as_str().unwrap(), "{c}");
    }
    for code in v["invalid_codes"].as_array().unwrap() {
        assert_eq!(failure::FailureClass::from_u32(code.as_u64().unwrap() as u32), Err(CmStatus::InvalidArgument));
    }
}

fn hex(s: &str) -> Vec<u8> {
    (0..s.len()).step_by(2).map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap()).collect()
}

#[test]
fn adb_devices_vectors() {
    let v = load("adb_devices.json");
    for c in v["cases"].as_array().unwrap() {
        let input = c.get("input_hex").map_or_else(|| c["input"].as_str().unwrap().as_bytes().to_vec(), |h| hex(h.as_str().unwrap()));
        let r = adb_devices::parse_devices(&input);
        match c.get("expect_status") {
            Some(s) => assert_eq!(outcome(r), *s, "{}", c["name"]),
            None => {
                let got = adb_devices::normalise(&r.unwrap());
                let want: String = c["expect"].as_array().unwrap().iter().map(|l| format!("{}\n", l.as_str().unwrap())).collect();
                assert_eq!(got, want, "{}", c["name"]);
            }
        }
    }
    for c in v["track_frames"].as_array().unwrap() {
        let r = adb_devices::track_frame(c["input"].as_str().unwrap().as_bytes());
        match c.get("expect_status") {
            Some(s) => assert_eq!(outcome(r), *s, "{c}"),
            None => assert_eq!(r.unwrap(), (c["expect_offset"].as_u64().unwrap() as usize, c["expect_len"].as_u64().unwrap() as usize)),
        }
    }
    let big = vec![b'a'; v["too_large_bytes"].as_u64().unwrap() as usize];
    assert_eq!(adb_devices::parse_devices(&big), Err(CmStatus::ParseTooLarge));
}
