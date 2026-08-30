//
//  StikJITHeadless.swift
//  StikJITHeadless
//
//  Created by Duy Tran on 30/8/26.
//

import Foundation
import StikJIT

@objc(StikJITWrapper) public class StikJITWrapper: NSObject {
    @objc public static func enableJIT(with pid: Int32, pairingFile: URL, ddiPath: URL, scriptString: String?) -> String {
        let ddiPaths = DDIPaths.default(in: ddiPath)
        let readiness = StikJIT.prepareDevice(pairingFile: pairingFile, paths: ddiPaths)
        switch readiness {
        case .ready(_):
            break
        case .unreachable(let reason):
            return "StikJIT.prepareDevice returned .unreachable: \(reason)"
        case .preparationFailed(let reason):
            return "StikJIT.prepareDevice returned .preparationFailed: \(reason)"
        @unknown default:
            return "Unknown error"
        }
        
        var script = StikJIT.Script.universal
        if let scriptString {
            let scriptURL = URL.temporaryDirectory.appending(component: "script.js")
            try? scriptString.write(to: scriptURL, atomically: true, encoding: .utf8)
            script = StikJIT.Script.custom(scriptURL)
        }
        
        do {
            try StikJIT.enableJIT(targetPID: pid, pairingFile: pairingFile, ddiPaths: ddiPaths, script: script, forceScript: false)
            return ""
        } catch {
            return error.localizedDescription
        }
    }
}
