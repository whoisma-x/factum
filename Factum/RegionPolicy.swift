import Foundation
import CoreTelephony

/// RegionPolicy centralizes geo-based feature gating to comply with regional laws.
///
/// - CallKit must be disabled in apps distributed on the China App Store (MIIT directive).
///   Use `RegionPolicy.isCallKitAllowed()` to guard any CallKit usage or registration.
/// - The detection below is best-effort and conservative: if the device is likely
///   in mainland China (based on language/region or carrier), we return false.
///   Server-side distribution targeting in App Store Connect should also exclude
///   China for builds that include CallKit features.
public enum RegionPolicy {
    /// Returns true if the device is likely located in mainland China.
    /// This uses a conservative heuristic based on:
    /// - The current locale's regionCode being "CN"
    /// - The first active carrier's isoCountryCode being "cn"
    public static func isChinaMainland() -> Bool {
        // Locale check
        if let regionCode = Locale.current.regionCode, regionCode.uppercased() == "CN" {
            return true
        }
        // Carrier check
        let netInfo = CTTelephonyNetworkInfo()
        if #available(iOS 16.0, *) {
            for carrier in netInfo.serviceSubscriberCellularProviders?.values ?? [] {
                if carrier.isoCountryCode?.lowercased() == "cn" { return true }
            }
        } else {
            if let carrier = netInfo.subscriberCellularProvider, carrier.isoCountryCode?.lowercased() == "cn" {
                return true
            }
        }
        return false
    }

    /// CallKit must be disabled in China mainland per MIIT request.
    public static func isCallKitAllowed() -> Bool {
        return !isChinaMainland()
    }
}
