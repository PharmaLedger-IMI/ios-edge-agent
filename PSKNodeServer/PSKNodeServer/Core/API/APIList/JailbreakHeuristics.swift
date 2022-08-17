//
//  JailbreakHeuristics.swift
//  PSKNodeServer
//
//  Created by Costin Andronache on 26.07.2022.
//

import Foundation
import PSSmartWalletNativeLayer

struct JailbreakHeuristics: APIImplementation {
    func perform(_ inputArguments: [APIValue], _ completion: @escaping APIResultCompletion) {
        let result: [String: Bool] = ["isProbablyJailbroken": isProbablyJailbroken()]
        guard let data = try? JSONEncoder().encode(result),
              let json = String(data: data, encoding: .ascii) else {
                  completion(.failure(APIError(code: "JAILBREAK_RESULT_ENCODING_ERROR")))
              return
        }
        completion(.success([.string(json)]))
    }
    
    func isProbablyJailbroken() -> Bool {
        Self.jailbreakApps.contains(where: isAccessible(path:)) ||
        canWriteToPrivate()
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
        "/bin/bash",
        "/usr/sbin/sshd",
        "/etc/apt",
        "/usr/bin/ssh",
        "/private/var/lib/apt",
        "/private/var/lib/cydia",
        "/private/var/tmp/cydia.log",
        "/Applications/WinterBoard.app",
        "/var/lib/cydia",
        "/private/etc/dpkg/origins/debian",
        "/bin.sh",
        "/private/etc/apt",
        "/etc/ssh/sshd_config",
        "/private/etc/ssh/sshd_config",
        "/Applications/SBSetttings.app",
        "/private/var/mobileLibrary/SBSettingsThemes/",
        "/private/var/stash",
        "/usr/libexec/sftp-server",
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
        "/usr/libexec/ssh-keysign",
        "/usr/libexec/sftp-server",
        "/Applications/blackra1n.app",
        "/Applications/IntelliScreen.app",
        "/Applications/Snoop-itConfig.app",
        "/var/checkra1n.dmg",
        "/var/binpack"
    ]
}
