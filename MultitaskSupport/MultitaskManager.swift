//
//  MultitaskManager.swift
//  LiveContainer
//
//  Created by s s on 2026/3/20.
//

enum MultitaskMode : Int {
    case virtualWindow = 0
    case nativeWindow = 1
}

@objc class MultitaskManager : NSObject {
    static private var runningApps: [String: UIViewController] = [:]
    static private var terminationWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    
    @objc class func registerMultitaskContainer(container: String, controller: UIViewController) {
        runningApps[container] = controller
    }
    
    @objc class func unregisterMultitaskContainer(container: String) {
        runningApps.removeValue(forKey: container)
        terminationWaiters.removeValue(forKey: container)?.forEach { $0.resume() }
    }
    
    @objc class func isUsing(container: String) -> Bool {
        return runningApps[container] != nil
    }
    
    @objc class func isMultitasking() -> Bool {
        return !runningApps.isEmpty
    }

    @MainActor class func terminate(container: String) async {
        guard #available(iOS 16.0, *), let controller = runningApps[container] as? AppSceneViewController else {
            return
        }
        await withCheckedContinuation { continuation in
            terminationWaiters[container, default: []].append(continuation)
            controller.terminate()
        }
    }
}
