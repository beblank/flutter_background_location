import Flutter
import UIKit
import CoreLocation
import Foundation

public class SwiftFlutterBackgroundLocationPlugin: NSObject, FlutterPlugin, CLLocationManagerDelegate {
    static var locationManager: CLLocationManager?
    static var channel: FlutterMethodChannel?


    private let MaxBGTime: TimeInterval = 5
    private let MinBGTime: TimeInterval = 2
    private let MinAcceptableLocationAccuracy: CLLocationAccuracy = 5
    private let WaitForLocationsTime: TimeInterval = 3
    
    private let manager = CLLocationManager()
    
    private var isManagerRunning = false
    private var checkLocationTimer: Timer?
    private var waitTimer: Timer?
    private var bgTask: UIBackgroundTaskIdentifier = UIBackgroundTaskInvalid
    private var lastLocations = [CLLocation]()
    
    public private(set) var acceptableLocationAccuracy: CLLocationAccuracy = 100
    public private(set) var checkLocationInterval: TimeInterval = 10
    public private(set) var isRunning = false

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = SwiftFlutterBackgroundLocationPlugin()

        SwiftFlutterBackgroundLocationPlugin.channel = FlutterMethodChannel(name: "flutter_background_location", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: SwiftFlutterBackgroundLocationPlugin.channel!)
        SwiftFlutterBackgroundLocationPlugin.channel?.setMethodCallHandler(instance.handle)
       
      
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        SwiftFlutterBackgroundLocationPlugin.locationManager = CLLocationManager()
        SwiftFlutterBackgroundLocationPlugin.locationManager?.delegate = self
        SwiftFlutterBackgroundLocationPlugin.locationManager?.requestAlwaysAuthorization()
        SwiftFlutterBackgroundLocationPlugin.channel?.invokeMethod("location", arguments: "method")
        
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.delegate = self

        if (call.method == "start_location_service") {
            SwiftFlutterBackgroundLocationPlugin.channel?.invokeMethod("location", arguments: "start_location_service")
            manager.startUpdatingLocation()
        } else if (call.method == "stop_location_service") {
            SwiftFlutterBackgroundLocationPlugin.channel?.invokeMethod("location", arguments: "stop_location_service")
            stopUpdatingLocation()
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if CLLocationManager.authorizationStatus() == .denied{
            print("Location service is disable...")
        }else{
            startLocationTracking()
        }
    }
    
    func startLocationTracking(){
        if CLLocationManager.authorizationStatus() == .authorizedAlways ||  CLLocationManager.authorizationStatus() == .authorizedWhenInUse{
            manager.startUpdatingLocation()
        }else if CLLocationManager.authorizationStatus() == .denied{
            print("Location service is disable")
        }else{
            manager.requestAlwaysAuthorization()
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Error \(error.localizedDescription)")
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = [
            "speed": locations.last!.speed,
            "altitude": locations.last!.altitude,
            "latitude": locations.last!.coordinate.latitude,
            "longitude": locations.last!.coordinate.longitude,
            "accuracy": locations.last!.horizontalAccuracy,
            "bearing": locations.last!.course
        ] as [String : Any]
        
        if waitTimer == nil {
            startWaitTimer()
        }

        SwiftFlutterBackgroundLocationPlugin.channel?.invokeMethod("location", arguments: location)
    }
    
    public func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }
    
    public func startUpdatingLocation(interval: TimeInterval, acceptableLocationAccuracy: CLLocationAccuracy = 100) {
        
        if isRunning {
            stopUpdatingLocation()
        }
        
        checkLocationInterval -= WaitForLocationsTime
        checkLocationInterval = interval > MaxBGTime ? MaxBGTime : interval
        checkLocationInterval = interval < MinBGTime ? MinBGTime : interval
        
        self.acceptableLocationAccuracy = acceptableLocationAccuracy < MinAcceptableLocationAccuracy ? MinAcceptableLocationAccuracy : acceptableLocationAccuracy
        
        isRunning = true
        
        addNotifications()
        startLocationManager()
    }
    
    public func stopUpdatingLocation() {
        isRunning = false
        stopWaitTimer()
        stopLocationManager()
        stopBackgroundTask()
        stopCheckLocationTimer()
        removeNotifications()
    }
    
    private func addNotifications() {
        
        removeNotifications()
        
        NotificationCenter.default.addObserver(self, selector:  #selector(applicationDidEnterBackground),
                                               name: NSNotification.Name.UIApplicationDidEnterBackground,
                                               object: nil)
        NotificationCenter.default.addObserver(self, selector:  #selector(applicationDidBecomeActive),
                                               name: NSNotification.Name.UIApplicationDidBecomeActive,
                                               object: nil)
    }
    
    private func removeNotifications() {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func startLocationManager() {
        isManagerRunning = true
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5
        manager.startUpdatingLocation()
    }
    
    private func pauseLocationManager(){
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = 99999
    }
    private func stopLocationManager() {
        isManagerRunning = false
        manager.stopUpdatingLocation()
    }
    
    @objc func applicationDidEnterBackground() {
        stopBackgroundTask()
        startBackgroundTask()
    }
    
    @objc func applicationDidBecomeActive() {
        stopBackgroundTask()
    }
    
    private func startCheckLocationTimer() {
        
        stopCheckLocationTimer()
        
        checkLocationTimer = Timer.scheduledTimer(timeInterval: checkLocationInterval, target: self, selector: #selector(checkLocationTimerEvent), userInfo: nil, repeats: false)
    }
    
    private func stopCheckLocationTimer() {
        if let timer = checkLocationTimer {
            timer.invalidate()
            checkLocationTimer=nil
        }
    }
    
    @objc func checkLocationTimerEvent() {
        stopCheckLocationTimer()
        startLocationManager()
        
        // starting from iOS 7 and above stop background task with delay, otherwise location service won't start
        self.perform(#selector(stopAndResetBgTaskIfNeeded), with: nil, afterDelay: 1)
    }
    
    private func startWaitTimer() {
        stopWaitTimer()
        
        waitTimer = Timer.scheduledTimer(timeInterval: WaitForLocationsTime, target: self, selector: #selector(waitTimerEvent), userInfo: nil, repeats: false)
    }
    
    private func stopWaitTimer() {
        
        if let timer = waitTimer {
            
            timer.invalidate()
            waitTimer=nil
        }
    }
    
    @objc func waitTimerEvent() {
        
        stopWaitTimer()
        
//        if acceptableLocationAccuracyRetrieved() {
            startBackgroundTask()
            startCheckLocationTimer()
            pauseLocationManager()
//        }else{
//            startWaitTimer()
//        }
    }
    
//    private func acceptableLocationAccuracyRetrieved() -> Bool {
//        let location = lastLocations.last!
//        return location.horizontalAccuracy <= acceptableLocationAccuracy ? true : false
//    }
    
    @objc func stopAndResetBgTaskIfNeeded()  {
        
        if isManagerRunning {
            stopBackgroundTask()
        }else{
            stopBackgroundTask()
            startBackgroundTask()
        }
    }
    
    private func startBackgroundTask() {
        let state = UIApplication.shared.applicationState
        
        if ((state == .background || state == .inactive) && bgTask == UIBackgroundTaskInvalid) {
            bgTask = UIApplication.shared.beginBackgroundTask(expirationHandler: {
                self.checkLocationTimerEvent()
            })
        }
    }
    
    @objc private func stopBackgroundTask() {
        guard bgTask != UIBackgroundTaskInvalid else { return }
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = UIBackgroundTaskInvalid
    }
}
