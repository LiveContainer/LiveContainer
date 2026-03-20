//
//  LCAppPreferenceView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/12/10.
//
import SwiftUI

protocol LCAppPreferencesDelegate {
    func get(key: String) -> AnyHashable?
    func set(key: String, val: AnyHashable?)
    func localize(_ key: String) -> String
}


struct PSTextField: View {
    let title : String
    let key : String
    let defaultValue : String?
    let delegate : LCAppPreferencesDelegate
    @State var val : String
    
    init(title: String, key: String, defaultValue: String?, delegate: LCAppPreferencesDelegate) {
        self.title = title
        self.key = key
        self.defaultValue = defaultValue
        self.delegate = delegate
        self._val = State(initialValue: delegate.get(key: key) as? String ?? defaultValue ?? "")
    }
    
    var body: some View {
        HStack {
            Text(delegate.localize(title))
            Spacer()
            TextField("", text: $val)
                .onSubmit {
                    delegate.set(key: key, val: val)
                }
                .multilineTextAlignment(.trailing)
        }
    }
    
}

struct PSTitleValue: View {
    let title : String
    let key : String
    let defaultValue : AnyHashable
    let values : [AnyHashable]?
    let titles : [String]?
    let displayValue : String
    let delegate : LCAppPreferencesDelegate
    
    init(title: String, key: String, defaultValue: AnyHashable, values: [AnyHashable]?, titles: [String]?, delegate: LCAppPreferencesDelegate) {
        self.title = title
        self.key = key
        self.defaultValue = defaultValue
        self.values = values
        self.titles = titles
        self.delegate = delegate
        let realValue = delegate.get(key: key)
        var defaultValueText = defaultValue as? String ?? ""
        let realValueText = realValue as? String ?? defaultValueText
        guard let values, let titles, values.count == titles.count else {
            displayValue = realValueText
            return
        }

        for i in 0..<values.count {
            let value = values[i]
            if value == defaultValue {
                defaultValueText = titles[i]
                break
            }
        }
        
        
        guard let realValue else {
            displayValue = defaultValueText
            
            return
        }

        
        for i in 0..<values.count {
            let value = values[i]
            if value == realValue {
                displayValue = titles[i]
                return
            }
        }
        displayValue = realValueText
    }
    
    var body: some View {
        HStack {
            Text(delegate.localize(title))
            Spacer()
            Text(delegate.localize(displayValue))
                .foregroundStyle(.secondary)
        }

    }
}

struct PSMultiValue: View {
    let title : String
    let key : String
    let defaultValue : AnyHashable
    let values : [AnyHashable]
    let titles : [String]
    let delegate : LCAppPreferencesDelegate
    @State var realValue : AnyHashable
    
    init(title: String, key: String, defaultValue: AnyHashable, values: [AnyHashable], titles: [String], delegate: LCAppPreferencesDelegate) {
        self.title = title
        self.key = key
        self.defaultValue = defaultValue
        self.values = values
        self.titles = titles
        self.delegate = delegate
        self._realValue = State(initialValue: delegate.get(key: key) ?? defaultValue)

    }
    
    var body: some View {
        Picker(delegate.localize(title), selection: $realValue) {
            ForEach(values.indices, id:\.self) { i in
                Text(delegate.localize(titles[i])).tag(values[i])
            }
        }
        .onChange(of: realValue) { newValue in
            delegate.set(key: key, val: realValue)
        }
    }
}

struct PSToggleSwitch: View {
    let title : String
    let key : String
    let defaultValue : AnyHashable
    let trueValue : AnyHashable
    let falseValue : AnyHashable
    let delegate : LCAppPreferencesDelegate
    @State var realValue : Bool = false
    
    init(title: String, key: String, defaultValue: AnyHashable, trueValue: AnyHashable?, falseValue: AnyHashable?, delegate: LCAppPreferencesDelegate) {
        self.title = title
        self.key = key
        self.defaultValue = defaultValue
        self.delegate = delegate
        self.trueValue = trueValue ?? true as AnyHashable
        self.falseValue = falseValue ?? false as AnyHashable
        let currentValue = delegate.get(key: key) ?? defaultValue
        if currentValue == self.trueValue {
            _realValue = State(initialValue: true)
        }
    }
    
    var body: some View {
        Toggle(delegate.localize(title), isOn: $realValue)
            .onChange(of: realValue) { newValue in
                delegate.set(key: key, val: newValue ? trueValue : falseValue)
            }
    }
}

struct PSSlider : View {
    let key : String
    let defaultValue : Float
    let minimumValue : Float
    let maximumValue : Float
    let delegate : LCAppPreferencesDelegate
    @State var realValue : Float
    
    init(key: String, defaultValue: Float, minimumValue: Float, maximumValue: Float, delegate: LCAppPreferencesDelegate) {
        self.key = key
        self.defaultValue = defaultValue
        self.minimumValue = minimumValue
        self.maximumValue = maximumValue
        self.delegate = delegate
        let currentValue = delegate.get(key: key) as? Float ?? defaultValue
        self._realValue = State(initialValue: currentValue)
    }
    
    var body: some View {
        Slider(value: $realValue, in:minimumValue...maximumValue, onEditingChanged: { c in
            if !c {
                delegate.set(key: key, val: realValue)
            }
        })
        
    }
}

struct PSChildPane: View {
    let title : String
    
    let rootPlistUrl : URL
    let bundleId : String
    let settingsBundle : Bundle
    let containerURL : URL
    
    let delegate : LCAppPreferencesDelegate
    
    var body: some View {
        NavigationLink {
            AppPreferencePageView(preferencePlistURL: rootPlistUrl, bundleId: bundleId, containerURL: containerURL, settingsBundle: settingsBundle)
                .navigationTitle(delegate.localize(title))
        } label: {
            Text(delegate.localize(title))
        }
    }
}

struct PSGroup: View {
    @State var children : [AnyView]
    let title : String
    let footerText : String
    let delegate : LCAppPreferencesDelegate
    
    var body: some View {
        Section {
            ForEach(children.indices, id: \.self) { i in
                children[i]
            }
        } header: {
            Text(delegate.localize(title))
        } footer: {
            Text(delegate.localize(footerText))
        }
    }
    
}

struct AppPreferencePageView : View {
    let preferencePlistURL : URL
    
    @State var children : [AnyView] = []
    @State var errorInfo : String?

    init(preferencePlistURL : URL, bundleId : String, containerURL : URL, settingsBundle: Bundle) {
        var children : [AnyView] = []
        self.preferencePlistURL = preferencePlistURL
        guard let dict = NSMutableDictionary(contentsOf: preferencePlistURL) else {
            errorInfo = "Failed to load preference."
            return
        }
        guard let items = dict["PreferenceSpecifiers"] as? [[String:Any]] else {
            errorInfo = "Failed to load preference."
            return
        }
        let suiteName = dict["ApplicationGroupContainerIdentifier"] as? String ?? bundleId
        let stringTable = dict["StringsTable"] as? String ?? nil
        
        let userDefaults = UserDefaults()._init(withSuiteName: suiteName, container: containerURL)!
        let delegate = AppPreferenceModel(settingsBundle: settingsBundle, userDefaults:userDefaults, table: stringTable)
        
        var currGroup : [String:Any]? = nil
        var currGroupChildren : [AnyView] = []
        for item in items {
            guard let type = item["Type"] as? String else {
                continue
            }
            var currView : (any View)?
            if type == "PSTitleValueSpecifier" {
                guard let title = item["Title"] as? String, let key = item["Key"] as? String, let defaultValue = item["DefaultValue"] as? AnyHashable else {
                    continue
                }
                currView = PSTitleValue(title: title, key: key, defaultValue: defaultValue, values: item["Values"] as? [AnyHashable], titles: item["Titles"] as? [String], delegate: delegate)
            } else if type == "PSTextFieldSpecifier" {
                guard let title = item["Title"] as? String, let key = item["Key"] as? String else {
                    continue
                }
                currView = PSTextField(title: title, key: key, defaultValue: item["DefaultValue"] as? String, delegate: delegate)
            } else if type == "PSMultiValueSpecifier" || type == "PSRadioGroupSpecifier" {
                guard let title = item["Title"] as? String, let key = item["Key"] as? String, let defaultValue = item["DefaultValue"] as? AnyHashable, let values = item["Values"] as? [AnyHashable], let titles = item["Titles"] as? [String] else {
                    continue
                }
                currView = PSMultiValue(title: title, key: key, defaultValue: defaultValue, values: values, titles: titles, delegate: delegate)
            } else if type == "PSToggleSwitchSpecifier" {
                guard let title = item["Title"] as? String, let key = item["Key"] as? String, let defaultValue = item["DefaultValue"] as? AnyHashable else {
                    continue
                }
                currView = PSToggleSwitch(title: title, key: key, defaultValue: defaultValue, trueValue: item["TrueValue"] as? AnyHashable, falseValue: item["FalseValue"] as? AnyHashable, delegate: delegate)
            } else if type == "PSSliderSpecifier" {
                guard let key = item["Key"] as? String, let defaultValue = item["DefaultValue"] as? Float, let minimumValue = item["MinimumValue"] as? Float, let maximumValue =  item["MaximumValue"] as? Float else {
                    continue
                }
                currView = PSSlider(key: key, defaultValue: defaultValue, minimumValue: minimumValue, maximumValue: maximumValue, delegate: delegate)
            } else if type == "PSChildPaneSpecifier"{
                guard let title = item["Title"] as? String, let file = item["File"] as? String else {
                    continue
                }
                let fileURL = preferencePlistURL.deletingLastPathComponent().appendingPathComponent(file).appendingPathExtension("plist")
                currView = PSChildPane(title: title, rootPlistUrl: fileURL, bundleId: bundleId, settingsBundle: settingsBundle, containerURL: containerURL, delegate: delegate)
                
            } else if type == "PSGroupSpecifier" {

                if let currGroup {
                    currView = PSGroup(children: currGroupChildren, title: currGroup["Title"] as? String ?? "", footerText: currGroup["FooterText"] as? String ?? "", delegate: delegate)
                    currGroupChildren = []
                }
                currGroup = item
            }
            guard let currView else {
                continue
            }
            if currGroup == nil || type == "PSGroupSpecifier" {
                    children.append(AnyView(currView))
            } else {
                currGroupChildren.append(AnyView(currView))
            }
        }
        if let currGroup {
            let currView = PSGroup(children: currGroupChildren, title: currGroup["Title"] as? String ?? "", footerText: currGroup["FooterText"] as? String ?? "", delegate: delegate)
            children.append(AnyView(currView))
        }
        self._children = State(initialValue: children)
    }
    
    var body: some View {
            Form {
                ForEach(children.indices, id: \.self) { i in
                    children[i]
                }
            }

    }
}

class AppPreferenceModel: LCAppPreferencesDelegate {
    let settingsBundle : Bundle
    let userDefaults : UserDefaults
    let table : String?
    private static var _enBundle : Bundle?
    private static var _enBundleFound = false
    private var enBundle : Bundle? {
        if AppPreferenceModel._enBundleFound {
            return AppPreferenceModel._enBundle;
        }
        let language = "en"
        let path = settingsBundle.path(forResource:language, ofType: "lproj")
        let bundle = Bundle(path: path!)
        AppPreferenceModel._enBundle = bundle
        AppPreferenceModel._enBundleFound = true
        return bundle
    }
    
    init(settingsBundle: Bundle, userDefaults: UserDefaults, table: String?) {
        self.settingsBundle = settingsBundle
        self.userDefaults = userDefaults
        self.table = table
    }
    
    func get(key: String) -> AnyHashable? {
        return self.userDefaults.object(forKey: key) as? AnyHashable ?? nil
    }
    
    func set(key: String, val: AnyHashable?) {
        self.userDefaults.set(val, forKey: key)
    }
    
    func localize(_ key: String) -> String {
        if let table {
            let message = NSLocalizedString(key, tableName: table, bundle: settingsBundle, comment: "")
            if message != key {
                return message
            }
            if let forcedString = enBundle?.localizedString(forKey: key, value: nil, table: table){
                return forcedString
            } else {
                return key
            }
        } else {
            return key
        }
        
    }
    
}

struct AppPreferenceView: View {
    let rootPlistUrl : URL
    let bundleId : String
    let settingsBundle : Bundle
    let containerURL : URL
    
    init(bundleId: String, settingsBundle: Bundle, containerURL: URL) {
        self.bundleId = bundleId
        self.settingsBundle = settingsBundle
        self.containerURL = containerURL
        self.rootPlistUrl = settingsBundle.bundleURL.appendingPathComponent("Root.plist")

    }

    var body: some View {
        AppPreferencePageView(preferencePlistURL: rootPlistUrl, bundleId: bundleId, containerURL : containerURL, settingsBundle: settingsBundle)
    }
}
