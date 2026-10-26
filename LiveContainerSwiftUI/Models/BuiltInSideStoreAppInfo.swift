//
//  BuiltInSideStoreAppInfo.swift
//  LiveContainer
//
//  Created by s s on 2026/4/12.
//

final class BuiltInSideStoreAppInfo : LCAppInfo {
    static let shared = BuiltInSideStoreAppInfo()
    static let launchBundleName = "builtinSideStore"
    static let launchURL = "livecontainer://livecontainer-launch?bundle-name=\(launchBundleName)"

    private override init() {
        super.init(bundlePath: Bundle.main.bundleURL.appendingPathComponent("Frameworks/SideStoreApp.framework").path)
        relativeBundlePath = Self.launchBundleName
    }

    override func homeScreenLaunchBundleName() -> String! {
        return Self.launchBundleName
    }
    
    override func iconIsDarkIcon(_ isDarkIcon: Bool) -> UIImage! {
        if isDarkIcon {
            if let cachedIconDark {
                return cachedIconDark
            }
            
        } else {
            if let cachedIcon {
                return cachedIcon
            }
        }
        guard let iconCacheUrl = ensureAndGetIconCacheFolder() else {
            return nil;
        }
        
        let cachedIconURL : URL;
        if(isDarkIcon) {
            cachedIconURL = iconCacheUrl.appendingPathComponent("LCAppIconDark.png");
        } else {
            cachedIconURL = iconCacheUrl.appendingPathComponent("LCAppIconLight.png");
        }
        
        var ans: UIImage? = nil
        if(FileManager.default.fileExists(atPath: cachedIconURL.path)) {
            ans = UIImage(contentsOfFile: cachedIconURL.path)
        }
        
        if let ans {
            return ans
        }
        
        ans = UIImage.generateIcon(forBundleURL: URL(fileURLWithPath: bundlePath()), style: isDarkIcon ? .Dark : .Light, hasBorder: true)
        if let ans {
            saveCGImage(ans.cgImage, cachedIconURL)
        }
        
        if isDarkIcon {
            cachedIconDark = ans
        } else {
            cachedIcon = ans
        }

        return ans;
    }
    
    override var lastLaunched: Date!{
        get {
            return nil
        }
        
        set {
            
        }
    }
    
    private func ensureAndGetIconCacheFolder() -> URL? {
        let directory = LCPath.docPath
            .appendingPathComponent("SideStore/Library/Caches", isDirectory: true)
            .appendingPathComponent("BuiltInSideStoreIconCache", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                return nil
            }
        }
        return directory
    }
}
