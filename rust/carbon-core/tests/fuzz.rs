//! Property tests: random and hostile input to every parser and validator must never panic.

use carbon_core::policy::{adb, net, size};
use carbon_core::protocol::adb_devices;
use proptest::prelude::*;

proptest! {
    #![proptest_config(ProptestConfig::with_cases(4096))]

    #[test]
    fn ip_check_never_panics(s in "\\PC{0,80}") {
        let _ = net::check_ip(&s);
        let _ = net::parse_host_port(&s);
    }

    #[test]
    fn adb_validate_never_panics(argv in proptest::collection::vec("\\PC{0,40}", 0..12), flags in any::<u32>()) {
        let refs: Vec<&str> = argv.iter().map(String::as_str).collect();
        let _ = adb::validate(&refs, flags);
    }

    #[test]
    fn device_list_never_panics(bytes in proptest::collection::vec(any::<u8>(), 0..4096)) {
        let _ = adb_devices::parse_devices(&bytes);
        let _ = adb_devices::track_frame(&bytes);
    }

    #[test]
    fn size_math_never_panics(a in any::<f64>(), b in any::<f64>(), c in any::<f64>(), d in any::<f64>()) {
        let s = size::CmSize { w: a, h: b };
        let i = size::CmInsets { top: c, left: d, bottom: c, right: d };
        let _ = size::clamp_scale(s, c, i, s);
        let _ = size::locked_resize(s, s, i, s, s);
        let _ = size::corner_radius(a, b, c, d);
    }

    #[test]
    fn clamped_scale_stays_in_limits(scale in 0.01f64..100.0) {
        let real = size::CmSize { w: 351.2, h: 781.9 };
        let none = size::CmInsets { top: 0.0, left: 0.0, bottom: 0.0, right: 0.0 };
        let (_, used) = size::clamp_scale(real, scale, none, size::CmSize { w: 4000.0, h: 4000.0 }).unwrap();
        prop_assert!((size::MIN_SCALE..=size::MAX_SCALE).contains(&used));
    }
}
