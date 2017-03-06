//
//  Siren.swift
//  Siren
//
//  Created by Arthur Sabintsev on 1/3/15.
//  Copyright (c) 2015 Sabintsev iOS Projects. All rights reserved.
//

import UIKit

// MARK: - SirenDelegate Protocol

public protocol SirenDelegate: class {
    func sirenDidShowUpdateDialog(alertType: SirenAlertType)   // User presented with update dialog
    func sirenUserDidLaunchAppStore()
    // User did click on button that launched App Store.app
    func sirenUserDidLaunchEnterpriseAppStore()
    // User did click on button that launched Enterprise App Store.app
    func sirenUserDidSkipVersion()                             // User did click on button that skips version update
    func sirenUserDidCancel()                                  // User did click on button that cancels update dialog
    func sirenDidFailVersionCheck(error: NSError)              // Siren failed to perform version check (may return system-level error)
    func sirenDidDetectNewVersionWithoutAlert(message: String) // Siren performed version check and did not display alert
    func sirenLatestVersionInstalled()                         // Siren performed version check and latest version is installed
}

// MARK: - SirenDelegate Protocol Extension

public extension SirenDelegate {
    func sirenDidShowUpdateDialog(alertType: SirenAlertType) {}
    func sirenUserDidLaunchAppStore() {}
    func sirenUserDidLaunchEnterpriseAppStore() {}
    func sirenUserDidSkipVersion() {}
    func sirenUserDidCancel() {}
    func sirenDidFailVersionCheck(error: NSError) {}
    func sirenDidDetectNewVersionWithoutAlert(message: String) {}
    func sirenLatestVersionInstalled() {}
}

/// Determines the type of alert to present after a successful version check has been performed.
///
/// - force: Forces user to update your app (1 button alert)
/// - option: (DEFAULT) Presents user with option to update app now or at next launch (2 button alert)
/// - skip: Presents user with option to update the app now, at next launch, or to skip this version all together (3 button alert)
/// - none: Doesn't show the alert, but instead returns a localized message for use in a custom UI within the sirenDidDetectNewVersionWithoutAlert() delegate method
public enum SirenAlertType {
    case force        // Forces user to update your app (1 button alert)
    case option       // (DEFAULT) Presents user with option to update app now or at next launch (2 button alert)
    case skip         // Presents user with option to update the app now, at next launch, or to skip this version all together (3 button alert)
    case none         // Doesn't show the alert, but instead returns a localized message for use in a custom UI within the sirenDidDetectNewVersionWithoutAlert() delegate method
}

/// Determines the frequency in which the the version check is performed
///
/// - immediately: Version check performed every time the app is launched.
/// - daily:  Version check performed once a day.
/// - weekly: Version check performed once a week.
public enum SirenVersionCheckType: Int {
    case immediately = 0    // Version check performed every time the app is launched
    case daily = 1          // Version check performed once a day
    case weekly = 7         // Version check performed once a week
}

/// Determines the available languages in which the update message and alert button titles should appear.
///
/// By default, the operating system's default lanuage setting is used. However, you can force a specific language
/// by setting the forceLanguageLocalization property before calling checkVersion()
public enum SirenLanguageType: String {
    case Arabic = "ar"
    case Armenian = "hy"
    case Basque = "eu"
    case ChineseSimplified = "zh-Hans"
    case ChineseTraditional = "zh-Hant"
    case Croatian = "hr"
    case Danish = "da"
    case Dutch = "nl"
    case English = "en"
    case Estonian = "et"
    case Finnish = "fi"
    case French = "fr"
    case German = "de"
    case Greek = "el"
    case Hebrew = "he"
    case Hungarian = "hu"
    case Indonesian = "id"
    case Italian = "it"
    case Japanese = "ja"
    case Korean = "ko"
    case Latvian = "lv"
    case Lithuanian = "lt"
    case Malay = "ms"
    case Norwegian = "nb-NO"
    case Polish = "pl"
    case PortugueseBrazil = "pt"
    case PortuguesePortugal = "pt-PT"
    case Russian = "ru"
    case SerbianCyrillic = "sr-Cyrl"
    case SerbianLatin = "sr-Latn"
    case Slovenian = "sl"
    case Spanish = "es"
    case Swedish = "sv"
    case Thai = "th"
    case Turkish = "tr"
    case Vietnamese = "vi"
}

/// Siren-specific Error Codes
private enum SirenErrorCode: Int {
    case malformedURL = 1000
    case recentlyCheckedAlready
    case noUpdateAvailable
    case appStoreDataRetrievalFailure
    case appStoreJSONParsingFailure
    case appStoreOSVersionNumberFailure
    case appStoreOSVersionUnsupported
    case appStoreVersionNumberFailure
    case appStoreVersionArrayFailure
    case appStoreAppIDFailure
}

/// Siren-specific Throwable Errors
private enum SirenError: Error {
    case malformedURL
    case missingBundleIdOrAppId
}

/// Siren-specific UserDefaults Keys
///
/// - StoredVersionCheckDate: Key that stores the timestamp of the last version check
/// - StoredSkippedVersion: Key that stores the version that a user decided to skip
private enum SirenUserDefaults: String {
    case StoredVersionCheckDate
    case StoredSkippedVersion
}

// MARK: - Siren

/// The Siren Class. A singleton that is initialized using the sharedInstance() method.
public final class Siren: NSObject {

    ///Current installed version of your app
    fileprivate var currentInstalledVersion: String? = {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }()

    /// The error domain for all errors created by Siren
    public let SirenErrorDomain = "Siren Error Domain"

    /// The SirenDelegate variable, which should be set if you'd like to be notified:
    ///
    /// When a user views or interacts with the alert
    /// - sirenDidShowUpdateDialog(alertType: SirenAlertType)
    /// - sirenUserDidLaunchAppStore()
    /// - sirenUserDidSkipVersion()
    /// - sirenUserDidCancel()
    ///
    /// When a new version has been detected, and you would like to present a localized message in a custom UI
    /// - sirenDidDetectNewVersionWithoutAlert(message: String)
    public weak var delegate: SirenDelegate?

    /// The debug flag, which is disabled by default.
    /// When enabled, a stream of println() statements are logged to your console when a version check is performed.
    public lazy var debugEnabled = false
    public var bEnterprise = true
    /// Determines the type of alert that should be shown.
    /// See the SirenAlertType enum for full details.
    public var alertType = SirenAlertType.option {
        didSet {
            majorUpdateAlertType = alertType
            minorUpdateAlertType = alertType
            patchUpdateAlertType = alertType
            revisionUpdateAlertType = alertType
        }
    }
    
    /// Determines the type of alert that should be shown for major version updates: A.b.c
    /// Defaults to SirenAlertType.Option.
    /// See the SirenAlertType enum for full details.
    public lazy var majorUpdateAlertType = SirenAlertType.option
    
    /// Determines the type of alert that should be shown for minor version updates: a.B.c
    /// Defaults to SirenAlertType.Option.
    /// See the SirenAlertType enum for full details.
    public lazy var minorUpdateAlertType  = SirenAlertType.option
    
    /// Determines the type of alert that should be shown for minor patch updates: a.b.C
    /// Defaults to SirenAlertType.Option.
    /// See the SirenAlertType enum for full details.
    public lazy var patchUpdateAlertType = SirenAlertType.option
    
    /// Determines the type of alert that should be shown for revision updates: a.b.c.D
    /// Defaults to SirenAlertType.Option.
    /// See the SirenAlertType enum for full details.
    public lazy var revisionUpdateAlertType = SirenAlertType.option

    /// The name of your app.
    /// By default, it's set to the name of the app that's stored in your plist.
    public lazy var appName: String = Bundle.main.bestMatchingAppName()

    /// The region or country of an App Store in which your app is available.
    /// By default, all version checks are performed against the US App Store.
    /// If your app is not available in the US App Store, set it to the identifier of at least one App Store within which it is available.
    public var countryCode: String?
    
    /// Overrides the default localization of a user's device when presenting the update message and button titles in the alert.
    /// See the SirenLanguageType enum for more details.
    public var forceLanguageLocalization: SirenLanguageType?
    
    /// Overrides the tint color for UIAlertController.
    public var alertControllerTintColor: UIColor?

    /// When this is set, the alert will only show up if the current version has already been released for X days
    public var showAlertAfterCurrentVersionHasBeenReleasedForDays: Int? = nil

    /// The current version of your app that is available for download on the App Store
    public fileprivate(set) var currentAppStoreVersion: String?

    fileprivate var appID: Int?
    fileprivate var lastVersionCheckPerformedOnDate: Date?
    fileprivate lazy var alertViewIsVisible: Bool = false
    fileprivate var updaterWindow: UIWindow?

    public static let sharedInstance = Siren()
    
    override init() {
        lastVersionCheckPerformedOnDate = UserDefaults.standard.object(forKey: SirenUserDefaults.StoredVersionCheckDate.rawValue) as? Date
    }

    /// Checks the currently installed version of your app against the App Store.
    /// The default check is against the US App Store, but if your app is not listed in the US,
    /// you should set the `countryCode` property before calling this method. Please refer to the countryCode property for more information.
    ///
    /// - Parameters:
    ///   - checkType: The frequency in days in which you want a check to be performed. Please refer to the SirenVersionCheckType enum for more details.
    public func checkVersion(checkType: SirenVersionCheckType) {
        guard let _ = Bundle.bundleID() else {
            printMessage(message: "Please make sure that you have set a `Bundle Identifier` in your project.")
            return
        }

        if checkType == .immediately {
            performVersionCheck()
        } else {
            guard let lastVersionCheckPerformedOnDate = lastVersionCheckPerformedOnDate else {
                performVersionCheck()
                return
            }
            
            if days(since: lastVersionCheckPerformedOnDate) >= checkType.rawValue {
                performVersionCheck()
            } else {
                postError(.recentlyCheckedAlready, underlyingError: nil)
            }
        }
    }
}

// MARK: - Helpers (Networking)

private extension Siren {

    func performVersionCheck() {
        do {
            //let url = try iTunesURLFromString()
            let url = try iEnterpriseURLFromString()
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringCacheData, timeoutInterval: 30)
            let task = URLSession.shared.dataTask(with: request, completionHandler: { [unowned self] (data, response, error) in
                if let error = error {
                    self.postError(.appStoreDataRetrievalFailure, underlyingError: error)
                } else {
                    guard let data = data else {
                        self.postError(.appStoreDataRetrievalFailure, underlyingError: nil)
                        return
                    }
                    var appData:[String: Any] = [String:Any]()
                    var dic:[String:Any] = [String:Any]()
                    do {
                        if(self.bEnterprise){
                            dic = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as! [String:Any]
                            //propertyListWithData(data!, options: 0, format: nil, error: &error)
                        }else {
                            let jsonData = try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions.allowFragments)
                            guard var appData = jsonData as? [String: Any]
                            else {
                                self.postError(.appStoreJSONParsingFailure, underlyingError: nil)
                                return
                            }
                            if(self.bEnterprise == false &&                                 self.isUpdateCompatibleWithDeviceOS(appData: appData) == false)
                            {
                                self.postError(.appStoreJSONParsingFailure, underlyingError: nil)
                                    return
                            }
                                //parse for <key>metadata</key>
                                       //     <key>bundle-version</key>
                                       //     <string>1.2</string>
                        }

                        DispatchQueue.main.async {
                            // Print iTunesLookup results from appData

                            // Process Results (e.g., extract current version that is available on the AppStore)
                            if(self.bEnterprise == false){
                                self.processVersionCheck(withResults: appData)
                            }else {
                                self.printMessage(message: "JSON results: \(appData)")
                                self.processEnterpriseVersionCheck(withResults:dic)
                            }
                        }

                    } catch let error as NSError {
                        self.postError(.appStoreDataRetrievalFailure, underlyingError: error)
                    }
                }
            })
          task.resume()
        } catch let error as NSError {
            postError(.malformedURL, underlyingError: error)
        }
    }

    func processVersionCheck(withResults results: [String: Any]) {
        storeVersionCheckDate() // Store version comparison date

        guard let allResults = results["results"] as? [[String: Any]] else {
            self.postError(.appStoreVersionNumberFailure, underlyingError: nil)
            return
        }

        /// Condition satisfied when app not in App Store
        guard !allResults.isEmpty else {
            postError(.appStoreDataRetrievalFailure, underlyingError: nil)
            return
        }

        guard let appID = allResults.first?["trackId"] as? Int else {
            postError(.appStoreAppIDFailure, underlyingError: nil)
            return
        }

        self.appID = appID

        guard let currentAppStoreVersion = allResults.first?["version"] as? String else {
            self.postError(.appStoreVersionArrayFailure, underlyingError: nil)
            return
        }

        self.currentAppStoreVersion = currentAppStoreVersion

        guard isAppStoreVersionNewer() else {
            delegate?.sirenLatestVersionInstalled()
            postError(.noUpdateAvailable, underlyingError: nil)
            return
        }
        
        guard let alertDays = showAlertAfterCurrentVersionHasBeenReleasedForDays else {
            showAlertIfCurrentAppStoreVersionNotSkipped()
            return
        }
        
        guard let currentVersionReleaseDate = allResults.first?["currentVersionReleaseDate"] as? String,
            let daysSinceRelease = days(since: currentVersionReleaseDate),
            daysSinceRelease >= alertDays else {
                return
        }
        
        showAlertIfCurrentAppStoreVersionNotSkipped()
        showAlertAfterCurrentVersionHasBeenReleasedForDays = nil
    }

    func processEnterpriseVersionCheck(withResults results: [String: Any]) {
//HERE        storeVersionCheckDate() // last time we did a comparison
        //items ->dictionary metadata
                    //metadata -> bundle-version
        let metaDataDic0 = results["items"] as! NSArray
//        for(i, in 0...metaDataDic0){
//            if(metaDataDic0[i] == "metadata")
//
//}
        let metaDataDic1 = metaDataDic0[0] as! [String: Any]
        let metaDataDic2 = metaDataDic1["metadata"] as! [String:Any]
        let versionNum0 = metaDataDic2["bundle-version"] as! String
        print(versionNum0)
        currentAppStoreVersion = versionNum0
    /*
        let metaDataDic:[String, Any] = results.object(forKey:"items" as String) as! <Dictionary:key [String, Any]>
        let versionNumber:String = metaDataDic.object(forKey:"bundle-version") as! String
        print(versionNumber)
    */
    /*
        guard let allResults = results["results"] as? [[String: Any]] else {
            self.postError(.appStoreVersionNumberFailure, underlyingError: nil)
            return
        }
        
        /// Condition satisfied when app not in App Store
        guard !allResults.isEmpty else {
            postError(.appStoreDataRetrievalFailure, underlyingError: nil)
            return
        }
 */
/*
        guard let appID = allResults.first?["trackId"] as? Int else {
            postError(.appStoreAppIDFailure, underlyingError: nil)
            return
        }
        
        self.appID = appID
        guard let currentAppStoreVersion = allResults.first?["version"] as? String else {
            self.postError(.appStoreVersionArrayFailure, underlyingError: nil)
            return
        }
        
        self.currentAppStoreVersion = currentAppStoreVersion
         */
        
        guard isAppStoreVersionNewer() else {
            delegate?.sirenLatestVersionInstalled()
            postError(.noUpdateAvailable, underlyingError: nil)
            return
        }
        
        guard let alertDays = showAlertAfterCurrentVersionHasBeenReleasedForDays else {
            showAlertIfCurrentAppStoreVersionNotSkipped()
            return
        }
/*
        guard let currentVersionReleaseDate = allResults.first?["currentVersionReleaseDate"] as? String,
            let daysSinceRelease = days(since: currentVersionReleaseDate),
            daysSinceRelease >= alertDays else {
                return
        }
 */
        showAlertIfCurrentAppStoreVersionNotSkipped()
        showAlertAfterCurrentVersionHasBeenReleasedForDays = nil
    }
    
    func iTunesURLFromString() throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/lookup"

        var items: [URLQueryItem] = [URLQueryItem(name: "bundleId", value: Bundle.bundleID())]

        if let countryCode = countryCode {
            let item = URLQueryItem(name: "country", value: countryCode)
            items.append(item)
        }

        components.queryItems = items

        guard let url = components.url, !url.absoluteString.isEmpty else {
            throw SirenError.malformedURL
        }
        
        return url
    }
    func iEnterpriseURLFromString() throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "ag.adient.com"
        //https://ag.adient.com/mobile/ios/sap-chargeback/manifest.plist
        components.path = "/mobile/ios/sap-chargeback/manifest.plist"
        
        //var items: [URLQueryItem] = [URLQueryItem(name: "bundleId", value: Bundle.bundleID())]
        
        /*if let countryCode = countryCode {
            let item = URLQueryItem(name: "country", value: countryCode)
            items.append(item)
        }
        
        components.queryItems = items
        */
        guard let url = components.url, !url.absoluteString.isEmpty else {
            throw SirenError.malformedURL
        }
        
        return url
    }
}

// MARK: - Helpers (Alert)

private extension Siren {
    func showAlertIfCurrentAppStoreVersionNotSkipped() {
        alertType = setAlertType()
        
        guard let previouslySkippedVersion = UserDefaults.standard.object(forKey: SirenUserDefaults.StoredSkippedVersion.rawValue) as? String else {
            showAlert()
            return
        }
        
        if let currentAppStoreVersion = currentAppStoreVersion, currentAppStoreVersion != previouslySkippedVersion {
            showAlert()
        }
    }
    
    func showAlert() {
        let updateAvailableMessage = Bundle().localizedString(stringKey: "Update Available", forceLanguageLocalization: forceLanguageLocalization)
        let newVersionMessage = localizedNewVersionMessage()

        let alertController = UIAlertController(title: updateAvailableMessage, message: newVersionMessage, preferredStyle: .alert)

        if let alertControllerTintColor = alertControllerTintColor {
            alertController.view.tintColor = alertControllerTintColor
        }

        switch alertType {
        case .force:
            alertController.addAction(updateAlertAction())
        case .option:
            alertController.addAction(nextTimeAlertAction())
            alertController.addAction(updateAlertAction())
        case .skip:
            alertController.addAction(nextTimeAlertAction())
            alertController.addAction(updateAlertAction())
            alertController.addAction(skipAlertAction())
        case .none:
            delegate?.sirenDidDetectNewVersionWithoutAlert(message: newVersionMessage)
        }
        
        if alertType != .none && !alertViewIsVisible{
            alertController.show()
            alertViewIsVisible = true
            delegate?.sirenDidShowUpdateDialog(alertType: alertType)
        }
    }
    
    func updateAlertAction() -> UIAlertAction {
        let title = localizedUpdateButtonTitle()
        let action = UIAlertAction(title: title, style: .default) { [unowned self] (alert: UIAlertAction) in
            self.hideWindow()
            if(self.bEnterprise){
                self.launchEnterpriseAppStore()
                self.delegate?.sirenUserDidLaunchEnterpriseAppStore()
            }else {
                self.launchAppStore()
                self.delegate?.sirenUserDidLaunchAppStore()
            }
            self.alertViewIsVisible = false
            return
        }
        
        return action
    }
    
    func nextTimeAlertAction() -> UIAlertAction {
        let title = localizedNextTimeButtonTitle()
        let action = UIAlertAction(title: title, style: .default) { [unowned self] (alert: UIAlertAction) in
            self.hideWindow()
            self.delegate?.sirenUserDidCancel()
            self.alertViewIsVisible = false
            return
        }
        
        return action
    }
    
    func skipAlertAction() -> UIAlertAction {
        let title = localizedSkipButtonTitle()
        let action = UIAlertAction(title: title, style: .default) { [unowned self] (alert: UIAlertAction) in

            if let currentAppStoreVersion = self.currentAppStoreVersion {
                UserDefaults.standard.set(currentAppStoreVersion, forKey: SirenUserDefaults.StoredSkippedVersion.rawValue)
                UserDefaults.standard.synchronize()
            }

            self.hideWindow()
            self.delegate?.sirenUserDidSkipVersion()
            self.alertViewIsVisible = false
            return
        }
        
        return action
    }

    func setAlertType() -> SirenAlertType {
        guard let currentInstalledVersion = currentInstalledVersion,
            let currentAppStoreVersion = currentAppStoreVersion else {
                return .option
        }

        let oldVersion = (currentInstalledVersion).characters.split {$0 == "."}.map { String($0) }.map {Int($0) ?? 0}
        let newVersion = (currentAppStoreVersion).characters.split {$0 == "."}.map { String($0) }.map {Int($0) ?? 0}

        guard let newVersionFirst = newVersion.first, let oldVersionFirst = oldVersion.first else {
            return alertType // Default value is .Option
        }

        if newVersionFirst > oldVersionFirst { // A.b.c.d
            alertType = majorUpdateAlertType
        } else if newVersion.count > 1 && (oldVersion.count <= 1 || newVersion[1] > oldVersion[1]) { // a.B.c.d
            alertType = minorUpdateAlertType
        } else if newVersion.count > 2 && (oldVersion.count <= 2 || newVersion[2] > oldVersion[2]) { // a.b.C.d
            alertType = patchUpdateAlertType
        } else if newVersion.count > 3 && (oldVersion.count <= 3 || newVersion[3] > oldVersion[3]) { // a.b.c.D
            alertType = revisionUpdateAlertType
        }
        
        return alertType
    }
}


// MARK: - Helpers (Localization)

private extension Siren {
    func localizedNewVersionMessage() -> String {
        let newVersionMessageToLocalize = "A new version of %@ is available. Please update to version %@ now."
        let newVersionMessage = Bundle().localizedString(stringKey: newVersionMessageToLocalize, forceLanguageLocalization: forceLanguageLocalization)

        guard let currentAppStoreVersion = currentAppStoreVersion else {
            return String(format: newVersionMessage, appName, "Unknown")
        }

        return String(format: newVersionMessage, appName, currentAppStoreVersion)
    }

    func localizedUpdateButtonTitle() -> String {
        return Bundle().localizedString(stringKey: "Update", forceLanguageLocalization: forceLanguageLocalization)
    }

    func localizedNextTimeButtonTitle() -> String {
        return Bundle().localizedString(stringKey: "Next time", forceLanguageLocalization: forceLanguageLocalization)
    }

    func localizedSkipButtonTitle() -> String {
        return Bundle().localizedString(stringKey: "Skip this version", forceLanguageLocalization: forceLanguageLocalization)
    }
}


// MARK: - Helpers (Version)

private extension Siren {
    func isAppStoreVersionNewer() -> Bool {
        var newVersionExists = false

        if let currentInstalledVersion = currentInstalledVersion,
            let currentAppStoreVersion = currentAppStoreVersion,
            (currentInstalledVersion.compare(currentAppStoreVersion, options: .numeric) == .orderedAscending) {

            newVersionExists = true
        }

        return newVersionExists
    }

    func storeVersionCheckDate() {
        lastVersionCheckPerformedOnDate = Date()
        if let lastVersionCheckPerformedOnDate = lastVersionCheckPerformedOnDate {
            UserDefaults.standard.set(lastVersionCheckPerformedOnDate, forKey: SirenUserDefaults.StoredVersionCheckDate.rawValue)
            UserDefaults.standard.synchronize()
        }
    }
}

// MARK: - Helpers (Date)

private extension Siren {
    static func setupDateFormatter() -> DateFormatter {
        let dateformatter = DateFormatter()
        dateformatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return dateformatter
    }

    func days(since date: Date) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: date, to: Date())
        return components.day!
    }

    func days(since dateString: String) -> Int? {
        let dateformatter = Siren.setupDateFormatter()
        guard let releaseDate = dateformatter.date(from: dateString) else { return nil }
        return days(since: releaseDate)
    }
}

// MARK: - Helpers (Misc.)

private extension Siren {
    func isUpdateCompatibleWithDeviceOS(appData: [String: Any]) -> Bool {
        guard let results = appData["results"] as? [[String: Any]],
            let requiredOSVersion = results.first?["minimumOsVersion"] as? String else {
                postError(.appStoreOSVersionNumberFailure, underlyingError: nil)
                return false
        }

        let systemVersion = UIDevice.current.systemVersion

        if systemVersion.compare(requiredOSVersion, options: .numeric) == .orderedDescending ||
            systemVersion.compare(requiredOSVersion, options: .numeric) == .orderedSame {
            return true
        } else {
            postError(.appStoreOSVersionUnsupported, underlyingError: nil)
            return false
        }
    }

    func hideWindow() {
        if let updaterWindow = updaterWindow {
            updaterWindow.isHidden = true
            self.updaterWindow = nil
        }
    }

    func launchEnterpriseAppStore(){
        let iEnterpriseString =  "https://ag.adient.com/mobile/index.html"
        let iEnterpriseURL = URL(string: iEnterpriseString)
        
        DispatchQueue.main.async {
            UIApplication.shared.openURL(iEnterpriseURL!)
        }
        
    }
    func launchAppStore() {
        guard let appID = appID else {
            return
        }

        let iTunesString =  "https://itunes.apple.com/app/id\(appID)"
        let iTunesURL = URL(string: iTunesString)

        DispatchQueue.main.async {
            UIApplication.shared.openURL(iTunesURL!)
        }

    }
    
    func printMessage(message: String) {
        if debugEnabled {
            print("[Siren] \(message)")
        }
    }
}

// MARK: - UIAlertController Extension

private extension UIAlertController {
    func show() {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = ViewController()
        window.windowLevel = UIWindowLevelAlert + 1
        
        Siren.sharedInstance.updaterWindow = window
        
        window.makeKeyAndVisible()
        window.rootViewController!.present(self, animated: true, completion: nil)
    }

    class ViewController: UIViewController {
        override var preferredStatusBarStyle: UIStatusBarStyle { return UIApplication.shared.statusBarStyle }
    }
}


// MARK: - Bundle Extension

private extension Bundle {
    class func bundleID() -> String? {
        return Bundle.main.bundleIdentifier
    }

    func sirenBundlePath() -> String {
        return Bundle(for: Siren.self).path(forResource: "Siren", ofType: "bundle") as String!
    }

    func sirenForcedBundlePath(forceLanguageLocalization: SirenLanguageType) -> String {
        let path = sirenBundlePath()
        let name = forceLanguageLocalization.rawValue
        return Bundle(path: path)!.path(forResource: name, ofType: "lproj")!
    }

    func localizedString(stringKey: String, forceLanguageLocalization: SirenLanguageType?) -> String {
        var path: String
        let table = "SirenLocalizable"
        if let forceLanguageLocalization = forceLanguageLocalization {
            path = sirenForcedBundlePath(forceLanguageLocalization: forceLanguageLocalization)
        } else {
            path = sirenBundlePath()
        }
        
        return Bundle(path: path)!.localizedString(forKey: stringKey, value: stringKey, table: table)
    }

    func bestMatchingAppName() -> String {
        let bundleDisplayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String

        return bundleDisplayName ?? bundleName ?? ""
    }
}


// MARK: - Error Handling

private extension Siren {
    func postError(_ code: SirenErrorCode, underlyingError: Error?) {
        let description: String

        switch code {
        case .malformedURL:
            description = "The iTunes URL is malformed. Please leave an issue on http://github.com/ArtSabintsev/Siren with as many details as possible."
        case .recentlyCheckedAlready:
            description = "Not checking the version, because it already checked recently."
        case .noUpdateAvailable:
            description = "No new update available."
        case .appStoreDataRetrievalFailure:
            description = "Error retrieving App Store data as an error was returned."
        case .appStoreJSONParsingFailure:
            description = "Error parsing App Store JSON data."
        case .appStoreOSVersionNumberFailure:
            description = "Error retrieving iOS version number as there was no data returned."
        case .appStoreOSVersionUnsupported:
            description = "The version of iOS on the device is lower than that of the one required by the app verison update."
        case .appStoreVersionNumberFailure:
            description = "Error retrieving App Store version number as there was no data returned."
        case .appStoreVersionArrayFailure:
            description = "Error retrieving App Store verson number as results.first does not contain a 'version' key."
        case .appStoreAppIDFailure:
            description = "Error retrieving trackId as results.first does not contain a 'trackId' key."
        }

        var userInfo: [String: Any] = [NSLocalizedDescriptionKey: description]
        
        if let underlyingError = underlyingError {
            userInfo[NSUnderlyingErrorKey] = underlyingError
        }

        let error = NSError(domain: SirenErrorDomain, code: code.rawValue, userInfo: userInfo)

        delegate?.sirenDidFailVersionCheck(error: error)

        printMessage(message: error.localizedDescription)
    }
}

// MARK: - Helpers (Testing Target)

extension Siren {
    func testSetCurrentInstalledVersion(version: String) {
        currentInstalledVersion = version
    }

    func testSetAppStoreVersion(version: String) {
        currentAppStoreVersion = version
    }

    func testIsAppStoreVersionNewer() -> Bool {
        return isAppStoreVersionNewer()
    }
}

extension Bundle {
    func testLocalizedString(stringKey: String, forceLanguageLocalization: SirenLanguageType?) -> String {
        return Bundle().localizedString(stringKey: stringKey, forceLanguageLocalization: forceLanguageLocalization)
    }
}
/*
 guard let appData = jsonData as? [String: Any],
 self.isUpdateCompatibleWithDeviceOS(appData: appData) else {
 
 self.postError(.appStoreJSONParsingFailure, underlyingError: nil)
 return
 }
*/
