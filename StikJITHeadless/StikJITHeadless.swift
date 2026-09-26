//
//  StikJITHeadless.swift
//  StikJITHeadless
//
//  Created by Duy Tran on 30/8/26.
//

import Foundation
import StikJIT

@objc(StikJITWrapper) public class StikJITWrapper: NSObject {
    @objc public static func enableJIT(with pid: Int32, timeout: TimeInterval, pairingFile: URL, ddiPath: URL, scriptJs: String?) -> String {
        let ddiPaths = DDIPaths.default(in: ddiPath)
        var script = StikJIT.Script.universal
        if let scriptJs {
            // script can either be built-in (hardcoded) paths or base64 string
            switch scriptJs {
            case "/Frameworks/StikJIT.framework/universal.js", "":
                // already specified universal as default
                break
            case "/Frameworks/StikJIT.framework/legacy.js":
                script = StikJIT.Script.legacy
                break
            default:
                script = StikJIT.Script.customBase64(scriptJs)
            }
        }
        
        do {
            let config = StikJIT.Configuration(connectionTimeout: timeout)
            try StikJIT.enableJIT(targetPID: pid, pairingFile: pairingFile, ddiPaths: ddiPaths,
                                  configuration: config, script: script, forceScript: false, progress: { progress in
                print(progress)
            })
            return ""
        } catch {
            return error.localizedDescription
        }
    }
}
