//
//  JailbreakHeuristics.swift
//  PSKNodeServer
//
//  Created by Costin Andronache on 26.07.2022.
//

import Foundation
import PSSmartWalletNativeLayer

struct JailbreakHeuristics: APIImplementation {
    enum Suspicion: Hashable {
        case containsJailbrokenApps([String])
        case canWriteToPrivateLocations
    }
    
    func perform(_ inputArguments: [APIValue], _ completion: @escaping APIResultCompletion) {
        let suspicions = jailbreakSuspicions()
        let result: [String: [String]] = ["jailbreakSuspicions": suspicions.map(\.localized)]
        
        guard let data = try? JSONEncoder().encode(result),
              let json = String(data: data, encoding: .ascii) else {
                  completion(.failure(APIError(code: "JAILBREAK_RESULT_ENCODING_ERROR")))
              return
        }
        completion(.success([.string(json)]))
    }
    
    func jailbreakSuspicions() -> Set<Suspicion> {
        var result = Set<Suspicion>()
        let apps = Self.jailbreakApps.filter(isAccessible(path:))
        
        if !apps.isEmpty {
            result.insert(.containsJailbrokenApps(apps))
        }
        
        if canWriteToPrivate() {
            result.insert(.canWriteToPrivateLocations)
        }

        return result
    }
}

private extension JailbreakHeuristics {
    func exists(path: String, isDirectory: Bool) -> Bool {
        let fm = FileManager.default
        var isDirectory: ObjCBool = ObjCBool(isDirectory)
        if fm.fileExists(atPath: path, isDirectory: &isDirectory) {
            return true
        }
        
        return false
    }
    
    func isAccessible(path: String) -> Bool {
        guard let ptr = fopen(path, "r") else {
            return exists(path: path, isDirectory: true) ||
            exists(path: path, isDirectory: false)
        }
        fclose(ptr)
        return true
    }
    
    func canWriteToPrivate() -> Bool {
        let text = "jailbreakTest";
        let path = "/private/jailbreakTest.txt"
        do {
            try text.write(to: URL(fileURLWithPath: path),
                           atomically: true,
                           encoding: .ascii)
            return true
        } catch {
            return false
        }
    }
}

private extension JailbreakHeuristics {
    static let jailbreakApps: [String] = [
        "/Application/Cydia.app",
        "/Library/MobileSubstrate/MobileSubstrate.dylib",
        "/etc/apt",
        "/private/var/lib/apt",
        "/private/var/lib/cydia",
        "/private/var/tmp/cydia.log",
        "/Applications/WinterBoard.app",
        "/var/lib/cydia",
        "/private/etc/dpkg/origins/debian",
        "/bin.sh",
        "/private/etc/apt",
        "/Applications/SBSetttings.app",
        "/private/var/mobileLibrary/SBSettingsThemes/",
        "/private/var/stash",
        "/usr/libexec/cydia/",
        "/usr/sbin/frida-server",
        "/usr/bin/cycript",
        "/usr/local/bin/cycript",
        "/usr/lib/libcycript.dylib",
        "/System/Library/LaunchDaemons/com.saurik.Cydia.Startup.plist",
        "/System/Library/LaunchDaemons/com.ikey.bbot.plist",
        "/Applications/FakeCarrier.app",
        "/Library/MobileSubstrate/DynamicLibraries/Veency.plist",
        "/Library/MobileSubstrate/DynamicLibraries/LiveClock.plist",
        "/Applications/blackra1n.app",
        "/Applications/IntelliScreen.app",
        "/Applications/Snoop-itConfig.app",
        "/var/checkra1n.dmg",
        "/var/binpack"
    ]
}

extension JailbreakHeuristics.Suspicion {
    var localized: String {
        switch self {
        case .canWriteToPrivateLocations:
            return "can_write_private_locations".localized
        case .containsJailbrokenApps(let apps):
            guard !apps.isEmpty else {
                return ""
            }
            return String(format: "contains_jailbreak_apps_format".localized,
                          "\(apps)")
        }
    }
}
