//
//  Main.swift
//  Nudge
//
//  Created by Erik Gomez on 2/2/21.
//

import UserNotifications
import SwiftUI
import CryptoKit

let windowDelegate = AppDelegate.WindowDelegate()
let dnc = DistributedNotificationCenter.default()
let nc = NotificationCenter.default
let snc = NSWorkspace.shared.notificationCenter
let bundle = Bundle.main
let serialNumber = Utils().getSerialNumber()

// Create an AppDelegate so that we can more finely control how Nudge operates
class AppDelegate: NSObject, NSApplicationDelegate {
    // This allows Nudge to terminate if all of the windows have been closed. It was needed when the close button was visible, but less needed now.
    // However if someone does close all the windows, we still want this.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillResignActive(_ notification: Notification) {
        // TODO: This function can be used to stop nudge from resigning its activation state
        // print("applicationWillResignActive")
    }
    
    func applicationDidResignActive(_ notification: Notification) {
        // TODO: This function can be used to force nudge right back in front if a user moves to another app
        // print("applicationDidResignActive")
    }

    func applicationWillBecomeActive(_ notification: Notification) {
        // TODO: Perhaps move some of the ContentView logic into this - Ex: updateUI()
        // print("applicationWillBecomeActive")
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // TODO: Perhaps move some of the ContentView logic into this - Ex: centering UI, full screen
        // print("applicationDidBecomeActive")
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Utils().centerNudge()
        // print("applicationDidFinishLaunching")

        // Observe all notifications generated by the default NotificationCenter
//        nc.addObserver(forName: nil, object: nil, queue: nil) { notification in
//            print("NotificationCenter: \(notification.name.rawValue), Object: \(notification)")
//        }
//        // Observe all notifications generated by the default DistributedNotificationCenter - No longer works as of Catalina
//        dnc.addObserver(forName: nil, object: nil, queue: nil) { notification in
//            print("DistributedNotificationCenter: \(notification.name.rawValue), Object: \(notification)")
//        }

        // Observe screen locking. Maybe useful later
        dnc.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { notification in
            utilsLog.info("\("Screen was locked", privacy: .public)")
        }

        dnc.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { notification in
            utilsLog.info("\("Screen was unlocked", privacy: .public)")
        }

        // Entering/leaving/exiting a full screen app or space
        snc.addObserver(
            self,
            selector: #selector(spacesStateChanged(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        
        snc.addObserver(
            self,
            selector: #selector(logHiddenApplication(_:)),
            name: NSWorkspace.didHideApplicationNotification,
            object: nil
        )

        if attemptToBlockApplicationLaunches {
            registerLocal()
            if !nudgeLogState.afterFirstLaunch && terminateApplicationsOnLaunch {
                terminateApplications()
            }
            snc.addObserver(
                self,
                selector: #selector(terminateApplicationSender(_:)),
                name: NSWorkspace.didLaunchApplicationNotification,
                object: nil
            )
        }

        // Listen for keyboard events
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            if self.detectBannedShortcutKeys(with: $0) {
                return nil
            } else {
                return $0
            }
        }
        
        if !nudgeLogState.afterFirstLaunch {
            nudgeLogState.afterFirstLaunch = true
            if NSWorkspace.shared.isActiveSpaceFullScreen() {
                NSApp.hide(self)
                // NSApp.windows.first?.resignKey()
                // NSApp.unhideWithoutActivation()
                // NSApp.deactivate()
                // NSApp.unhideAllApplications(nil)
                // NSApp.hideOtherApplications(self)
            }
        }
    }

    @objc func logHiddenApplication(_ notification: Notification) {
        utilsLog.info("\("Application hidden", privacy: .public)")
    }

    @objc func spacesStateChanged(_ notification: Notification) {
        Utils().centerNudge()
        utilsLog.info("\("Spaces state changed", privacy: .public)")
        nudgePrimaryState.afterFirstStateChange = true
    }

    @objc func terminateApplicationSender(_ notification: Notification) {
        utilsLog.info("\("Application launched", privacy: .public)")
        terminateApplications()
    }

    func terminateApplications() {
        if !Utils().pastRequiredInstallationDate() {
            return
        }
        utilsLog.info("\("Application launched", privacy: .public)")
        for runningApplication in NSWorkspace.shared.runningApplications {
            let appBundleID = runningApplication.bundleIdentifier ?? ""
            let appName = runningApplication.localizedName ?? ""
            if appBundleID == "com.github.macadmins.Nudge" {
                continue
            }
            if blockedApplicationBundleIDs.contains(appBundleID) {
                utilsLog.info("\("Found \(appName), terminating application", privacy: .public)")
                scheduleLocal(applicationIdentifier: appName)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.001, execute: {
                    runningApplication.forceTerminate()
                })
            }
        }
    }
    
    @objc func registerLocal() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .provisional, .sound]) { (granted, error) in
            if granted {
                uiLog.info("\("User granted notifications - application blocking status now available", privacy: .public)")
            } else {
                uiLog.info("\("User denied notifications - application blocking status will be unavailable", privacy: .public)")
            }
        }
    }

    @objc func scheduleLocal(applicationIdentifier: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { (settings) in
            let content = UNMutableNotificationContent()
            content.title = "Application terminated".localized(desiredLanguage: getDesiredLanguage())
            content.subtitle = "(\(applicationIdentifier))"
            content.body = "Please update your device to use this application".localized(desiredLanguage: getDesiredLanguage())
            content.categoryIdentifier = "alert"
            content.sound = UNNotificationSound.default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.001, repeats: false)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
            switch settings.authorizationStatus {
                
            case .authorized:
                center.add(request)
            case .denied:
                uiLog.info("\("Application terminated without user notification", privacy: .public)")
            case .notDetermined:
                uiLog.info("\("Application terminated without user notification status", privacy: .public)")
            case .provisional:
                uiLog.info("\("Application terminated with provisional user notification status", privacy: .public)")
                center.add(request)
            @unknown default:
                uiLog.info("\("Application terminated with unknown user notification status", privacy: .public)")
            }
        }
    }
    
    func detectBannedShortcutKeys(with event: NSEvent) -> Bool {
        // Only detect shortcut keys if Nudge is active - adapted from https://stackoverflow.com/questions/32446978/swift-capture-keydown-from-nsviewcontroller/40465919
        if NSApplication.shared.isActive {
            switch event.modifierFlags.intersection(.deviceIndependentFlagsMask) {
                // Disable CMD + W - closes the Nudge window and breaks it
                case [.command] where event.characters == "w":
                    uiLog.warning("\("Nudge detected an attempt to close the application via CMD + W shortcut key.", privacy: .public)")
                    return true
                // Disable CMD + N - closes the Nudge window and breaks it
                case [.command] where event.characters == "n":
                    uiLog.warning("\("Nudge detected an attempt to create a new window via CMD + N shortcut key.", privacy: .public)")
                    return true
                // Disable CMD + M - closes the Nudge window and breaks it
                case [.command] where event.characters == "m":
                    uiLog.warning("\("Nudge detected an attempt to minimise the application via CMD + M shortcut key.", privacy: .public)")
                    return true
                // Disable CMD + Q -  fully closes Nudge
                case [.command] where event.characters == "q":
                    uiLog.warning("\("Nudge detected an attempt to close the application via CMD + Q shortcut key.", privacy: .public)")
                    return true
                // Don't care about any other shortcut keys
                default:
                    return false
            }
        }
        return false
    }
    
    // Only exit if primaryQuitButton is clicked
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if nudgePrimaryState.shouldExit {
            return NSApplication.TerminateReply.terminateNow
        } else {
            uiLog.warning("\("Nudge detected an attempt to exit the application.", privacy: .public)")
            return NSApplication.TerminateReply.terminateCancel
        }
    }

    func runSoftwareUpdate() {
        if Utils().demoModeEnabled() || Utils().unitTestingEnabled() {
            return
        }

        if asynchronousSoftwareUpdate && Utils().requireMajorUpgrade() == false {
            DispatchQueue(label: "nudge-su", attributes: .concurrent).asyncAfter(deadline: .now(), execute: {
                SoftwareUpdate().Download()
            })
        } else {
            SoftwareUpdate().Download()
        }
    }

    // Pre-Launch Logic
    func applicationWillFinishLaunching(_ notification: Notification) {
        if FileManager.default.fileExists(atPath: "/Library/Managed Preferences/com.github.macadmins.Nudge.json.plist") {
            prefsProfileLog.warning("\("Found bad profile path at /Library/Managed Preferences/com.github.macadmins.Nudge.json.plist", privacy: .public)")
            exit(1)
        }

        let configJSON = Utils().getConfigurationAsJSON()
        let configProfile = Utils().getConfigurationAsProfile()
        
        if CommandLine.arguments.contains("-print-profile-config") {
            if !configProfile.isEmpty {
                print(String(data: configProfile, encoding: .utf8) as AnyObject)
            }
            exit(0)
        } else if CommandLine.arguments.contains("-print-json-config") {
            if !configJSON.isEmpty {
                print(String(decoding: configJSON, as: UTF8.self))
            }
            exit(0)
        }

        // print("applicationWillFinishLaunching")
        _ = Utils().gracePeriodLogic()
        // metrics
        if !(serialNumber.count > 20) { // if greater than 20, assume some weird VM and don't ship data
            var metricsHash = [String: String]()
            // serial in a uuid-like design (8-4-4-4-12)
            var serialUUIDString = ""
            for (index, value) in serialNumber.map({ String($0) }).enumerated() {
                if index >= 0 && index <= 7 {
                    serialUUIDString.append(value)
                } else if index == 8 {
                    serialUUIDString.append("-\(value)")
                } else if index >= 9 && index <= 11 {
                    serialUUIDString.append(value)
                } else if index == 12 {
                    serialUUIDString.append("-\(value)")
                } else if index >= 13 && index <= 15 {
                    serialUUIDString.append(value)
                } else if index == 16 {
                    serialUUIDString.append("-\(value)")
                } else if index >= 17 && index <= 19 {
                    serialUUIDString.append(value)
                }
            }
            if serialNumber.count == 10 {
                serialUUIDString.append("00-0000-0000-000000000000")
            } else if serialNumber.count == 11 {
                serialUUIDString.append("0-0000-0000-000000000000")
            } else if serialNumber.count == 12 {
                serialUUIDString.append("-0000-0000-000000000000")
            } else if serialNumber.count == 13 {
                serialUUIDString.append("000-0000-000000000000")
            } else if serialNumber.count == 14 {
                serialUUIDString.append("00-0000-000000000000")
            } else if serialNumber.count == 15 {
                serialUUIDString.append("0-0000-000000000000")
            } else if serialNumber.count == 16 {
                serialUUIDString.append("-0000-000000000000")
            } else if serialNumber.count == 17 {
                serialUUIDString.append("000-000000000000")
            } else if serialNumber.count == 18 {
                serialUUIDString.append("00-000000000000")
            } else if serialNumber.count == 19 {
                serialUUIDString.append("0-000000000000")
            } else if serialNumber.count == 20 {
                serialUUIDString.append("-000000000000")
            }
            
            // Take the hardware uuid + pseudo fake serial uuid, merge them into a long string with a nudge namespace for increased uniqueness and then convert them to a hash
            let stringHash = SHA256.hash(data: Data(("com.github.macadmins.Nudge:" + Utils().getHardwareUUID() + serialUUIDString).utf8))
            // Take the first 16 values and convert it to a uuid. This shouldn't change unless a logic board is replaced but also doesn't leak any information to the server
            metricsHash["deviceID"] = NSUUID(uuidBytes: Array(stringHash.prefix(16))).uuidString

            // path to Nudge
            metricsHash["bundlePath"] = bundle.bundlePath
            // hash of config
            if !configJSON.isEmpty {
                metricsHash["configJSON"] = MD5(string: String(decoding: configJSON, as: UTF8.self))
            }
            if !configProfile.isEmpty {
                metricsHash["configProfile"] = MD5(string: String(data: configProfile, encoding: .utf8)!)
            }
            // code signature name
            if Utils().getSigningInfo() != nil {
                metricsHash["developerCertificate"] = Utils().getSigningInfo()!
            }
            // version of app
            metricsHash["appVersion"] = Utils().getNudgeVersion()
            
            // TODO: ship the data somewhere (save data to NSUserDefaults) - only ship data when config, version of code sig has changed
        }

        if nudgePrimaryState.shouldExit {
            exit(0)
        }

        if randomDelay {
            let randomDelaySeconds = Int.random(in: 1...maxRandomDelayInSeconds)
            uiLog.notice("Delaying initial run (in seconds) by: \(String(randomDelaySeconds), privacy: .public)")
            sleep(UInt32(randomDelaySeconds))
        }

        self.runSoftwareUpdate()
        if Utils().requireMajorUpgrade() {
            if actionButtonPath != nil {
                if !actionButtonPath!.isEmpty {
                    return
                } else {
                    prefsProfileLog.warning("\("actionButtonPath contains empty string - actionButton will be unable to trigger any action required for major upgrades", privacy: .public)")
                    return
                }
            }

            if attemptToFetchMajorUpgrade == true && fetchMajorUpgradeSuccessful == false && (majorUpgradeAppPathExists == false && majorUpgradeBackupAppPathExists == false) {
                uiLog.error("\("Unable to fetch major upgrade and application missing, exiting Nudge", privacy: .public)")
                nudgePrimaryState.shouldExit = true
                exit(1)
            } else if attemptToFetchMajorUpgrade == false && (majorUpgradeAppPathExists == false && majorUpgradeBackupAppPathExists == false) {
                uiLog.error("\("Unable to find major upgrade application, exiting Nudge", privacy: .public)")
                nudgePrimaryState.shouldExit = true
                exit(1)
            }
        }
    }
    
    class WindowDelegate: NSObject, NSWindowDelegate {
        func windowDidMove(_ notification: Notification) {
            Utils().centerNudge()
        }
        func windowDidChangeScreen(_ notification: Notification) {
            Utils().centerNudge()
        }
    }
}

@main
struct Main: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var viewState = nudgePrimaryState
    
    var declaredWindowHeight: CGFloat = 450
    var declaredWindowWidth: CGFloat = 900
    
    var body: some Scene {
        WindowGroup {
            if Utils().debugUIModeEnabled() {
                VSplitView {
                    ContentView(viewObserved: viewState)
                        .frame(width: declaredWindowWidth, height: declaredWindowHeight)
                    ContentView(viewObserved: viewState, forceSimpleMode: true)
                        .frame(width: declaredWindowWidth, height: declaredWindowHeight)
                }
                .frame(height: declaredWindowHeight*2)
            } else {
                ContentView(viewObserved: viewState)
                    .frame(width: declaredWindowWidth, height: declaredWindowHeight)
            }
        }
        // Hide Title Bar
        .windowStyle(.hiddenTitleBar)
    }
}

func MD5(string: String) -> String {
    let digest = Insecure.MD5.hash(data: string.data(using: .utf8) ?? Data())

    return digest.map {
        String(format: "%02hhx", $0)
    }.joined()
}

