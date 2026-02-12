import Flutter
import UIKit
import CallKit
import AVFoundation
import UserNotifications

@available(iOS 10.0, *)
public class SwiftFlutterCallkitIncomingPlugin: NSObject, FlutterPlugin, CXProviderDelegate, CXCallObserverDelegate {
    
    static let ACTION_DID_UPDATE_DEVICE_PUSH_TOKEN_VOIP = "com.hiennv.flutter_callkit_incoming.DID_UPDATE_DEVICE_PUSH_TOKEN_VOIP"
    
    static let ACTION_CALL_INCOMING = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_INCOMING"
    static let ACTION_CALL_START = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_START"
    static let ACTION_CALL_ACCEPT = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_ACCEPT"
    static let ACTION_CALL_DECLINE = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_DECLINE"
    static let ACTION_CALL_ENDED = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_ENDED"
    static let ACTION_CALL_TIMEOUT = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TIMEOUT"
    static let ACTION_CALL_CALLBACK = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_CALLBACK"
    static let ACTION_CALL_CUSTOM = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_CUSTOM"
    static let ACTION_CALL_CONNECTED = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_CONNECTED"
    
    static let ACTION_CALL_TOGGLE_HOLD = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_HOLD"
    static let ACTION_CALL_TOGGLE_MUTE = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_MUTE"
    static let ACTION_CALL_TOGGLE_DMTF = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_DMTF"
    static let ACTION_CALL_TOGGLE_GROUP = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_GROUP"
    static let ACTION_CALL_TOGGLE_AUDIO_SESSION = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_AUDIO_SESSION"
    
    @objc public private(set) static var sharedInstance: SwiftFlutterCallkitIncomingPlugin!
    
    private var streamHandlers: WeakArray<EventCallbackHandler> = WeakArray([])
    
    private var callManager: CallManager
    
    private var sharedProvider: CXProvider? = nil
    
    private var outgoingCall : Call?
    private var answerCall : Call?
    
    // 🗑️ Removed global state variables
    // private var data: Data?
    // private var isFromPushKit: Bool = false
    
    private var silenceEvents: Bool = false
    private let devicePushTokenVoIP = "DevicePushTokenVoIP"
    private let callObserver = CXCallObserver()
    
    private func sendEvent(_ event: String, _ body: [String : Any?]?) {
        if silenceEvents {
            print(event, " silenced")
            return
        } else {
            streamHandlers.reap().forEach { handler in
                handler?.send(event, body ?? [:])
            }
        }
        
    }
    
    @objc public func sendEventCustom(_ event: String, body: NSDictionary?) {
        streamHandlers.reap().forEach { handler in
            handler?.send(event, body ?? [:])
        }
    }
    
    public static func sharePluginWithRegister(with registrar: FlutterPluginRegistrar) {
        if(sharedInstance == nil){
            sharedInstance = SwiftFlutterCallkitIncomingPlugin(messenger: registrar.messenger())
        }
        sharedInstance.shareHandlers(with: registrar)
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        sharePluginWithRegister(with: registrar)
    }
    
    private static func createMethodChannel(messenger: FlutterBinaryMessenger) -> FlutterMethodChannel {
        return FlutterMethodChannel(name: "flutter_callkit_incoming", binaryMessenger: messenger)
    }
    
    private static func createEventChannel(messenger: FlutterBinaryMessenger) -> FlutterEventChannel {
        return FlutterEventChannel(name: "flutter_callkit_incoming_events", binaryMessenger: messenger)
    }
    
    public init(messenger: FlutterBinaryMessenger) {
        callManager = CallManager()
        super.init()
        callObserver.setDelegate(self, queue: nil)
        
    }
    // MARK: - CXCallObserverDelegate
    public func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        // 셀룰러 콜(우리 VoIP 콜이 아닌 것)이 끊겼는지 감지
        let isOurCall = self.callManager.callWithUUID(uuid: call.uuid) != nil
        
        if !isOurCall && call.hasEnded {
            // 셀룰러 콜이 종료됨 → hold 중인 VoIP 콜을 unhold
            for managedCall in self.callManager.calls {
                if managedCall.isOnHold {
                    self.callManager.holdCall(call: managedCall, onHold: false)
                }
            }
        }
        
    }
    private func shareHandlers(with registrar: FlutterPluginRegistrar) {
        registrar.addMethodCallDelegate(self, channel: Self.createMethodChannel(messenger: registrar.messenger()))
        let eventsHandler = EventCallbackHandler()
        self.streamHandlers.append(eventsHandler)
        Self.createEventChannel(messenger: registrar.messenger()).setStreamHandler(eventsHandler)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "showCallkitIncoming":
            guard let args = call.arguments else {
                result(true)
                return
            }
            if let getArgs = args as? [String: Any] {
                let data = Data(args: getArgs)
                showCallkitIncoming(data, fromPushKit: false)
            }
            result(true)
            break
        case "showMissCallNotification":
            guard let args = call.arguments else {
                result(true)
                return
            }
            if let getArgs = args as? [String: Any] {
                let data = Data(args: getArgs)
                self.showMissedCallNotification(data)
            }
            result(true)
            break
        case "startCall":
            guard let args = call.arguments else {
                result(true)
                return
            }
            if let getArgs = args as? [String: Any] {
                let data = Data(args: getArgs)
                self.startCall(data, fromPushKit: false)
            }
            result(true)
            break
        case "endCall":
            guard let args = call.arguments else {
                result(true)
                return
            }
            // ✅ Logic changed: Create temporary data from args to identify which call to end
            if let getArgs = args as? [String: Any] {
                let data = Data(args: getArgs)
                self.endCall(data)
            }
            result(true)
            break
        case "muteCall":
            guard let args = call.arguments as? [String: Any] ,
                  let callId = args["id"] as? String,
                  let isMuted = args["isMuted"] as? Bool else {
                result(true)
                return
            }
            
            self.muteCall(callId, isMuted: isMuted)
            result(true)
            break
        case "isMuted":
            guard let args = call.arguments as? [String: Any] ,
                  let callId = args["id"] as? String else{
                result(false)
                return
            }
            guard let callUUID = UUID(uuidString: callId),
                  let call = self.callManager.callWithUUID(uuid: callUUID) else {
                result(false)
                return
            }
            result(call.isMuted)
            break
        case "holdCall":
            guard let args = call.arguments as? [String: Any] ,
                  let callId = args["id"] as? String,
                  let onHold = args["isOnHold"] as? Bool else {
                result(true)
                return
            }
            self.holdCall(callId, onHold: onHold)
            result(true)
            break
        case "callConnected":
            guard let args = call.arguments else {
                result(true)
                return
            }
            if let getArgs = args as? [String: Any] {
                let data = Data(args: getArgs)
                self.connectedCall(data)
            }
            result(true)
            break
        case "activeCalls":
            result(self.callManager.activeCalls())
            break;
        case "endAllCalls":
            self.callManager.endCallAlls()
            result(true)
            break
        case "getDevicePushTokenVoIP":
            result(self.getDevicePushTokenVoIP())
            break;
        case "silenceEvents":
            guard let silence = call.arguments as? Bool else {
                result(true)
                return
            }
            
            self.silenceEvents = silence
            result(true)
            break;
        case "requestNotificationPermission":
            guard let args = call.arguments else {
                result(true)
                return
            }
            if let getArgs = args as? [String: Any] {
                self.requestNotificationPermission(getArgs)
            }
            result(true)
            break
         case "requestFullIntentPermission": 
            result(true)
            break
         case "canUseFullScreenIntent": 
            result(true)
            break
        case "hideCallkitIncoming":
            result(true)
            break
        case "endNativeSubsystemOnly":
            result(true)
            break
        case "setAudioRoute":
            result(true)
            break
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    @objc public func setDevicePushTokenVoIP(_ deviceToken: String) {
        UserDefaults.standard.set(deviceToken, forKey: devicePushTokenVoIP)
        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_DID_UPDATE_DEVICE_PUSH_TOKEN_VOIP, ["deviceTokenVoIP":deviceToken])
    }
    
    @objc public func getDevicePushTokenVoIP() -> String {
        return UserDefaults.standard.string(forKey: devicePushTokenVoIP) ?? ""
    }
    
    @objc public func getAcceptedCall() -> Data? {
        // ✅ Logic changed: Return the data of the currently answered call
        return self.answerCall?.data
    }
    
    @objc public func showCallkitIncoming(_ data: Data, fromPushKit: Bool) {
        // 🗑️ Removed self.data = data
        // self.isFromPushKit = fromPushKit // Removed
        
        if(data.isShowMissedCallNotification){
            CallkitNotificationManager.shared.addNotificationCategory(data.missedNotificationCallbackText)
        }
        
        var handle: CXHandle?
        handle = CXHandle(type: self.getHandleType(data.handleType), value: data.getEncryptHandle())
        
        let callUpdate = CXCallUpdate()

        callUpdate.remoteHandle = handle
        callUpdate.supportsDTMF = data.supportsDTMF
        callUpdate.supportsHolding = data.supportsHolding
        callUpdate.supportsGrouping = data.supportsGrouping
        callUpdate.supportsUngrouping = data.supportsUngrouping
        callUpdate.hasVideo = data.type > 0 ? true : false
        callUpdate.localizedCallerName = data.nameCaller
        
        initCallkitProvider(data)
        
        let uuid = UUID(uuidString: data.uuid)
        
        // ✅ Pass data explicitly to configureAudioSession
        self.configureAudioSession(data: data)
        
        self.sharedProvider?.reportNewIncomingCall(with: uuid!, update: callUpdate) { error in
            if(error == nil) {
                self.configureAudioSession(data: data)
                let call = Call(uuid: uuid!, data: data)
                call.handle = data.handle
                self.callManager.addCall(call)
                self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_INCOMING, data.toJSON())
                self.endCallNotExist(data)
            }
        }
    }
    
    @objc public func showCallkitIncoming(_ data: Data, fromPushKit: Bool, completion: @escaping () -> Void) {
        // 🗑️ Removed self.data = data
        
        if(data.isShowMissedCallNotification){
            CallkitNotificationManager.shared.addNotificationCategory(data.missedNotificationCallbackText)
        }
        
        var handle: CXHandle?
        handle = CXHandle(type: self.getHandleType(data.handleType), value: data.getEncryptHandle())
        
        let callUpdate = CXCallUpdate()
        callUpdate.remoteHandle = handle
        callUpdate.supportsDTMF = data.supportsDTMF
        callUpdate.supportsHolding = data.supportsHolding
        callUpdate.supportsGrouping = data.supportsGrouping
        callUpdate.supportsUngrouping = data.supportsUngrouping
        callUpdate.hasVideo = data.type > 0 ? true : false
        callUpdate.localizedCallerName = data.nameCaller
        
        initCallkitProvider(data)
        
        let uuid = UUID(uuidString: data.uuid)
        
        self.sharedProvider?.reportNewIncomingCall(with: uuid!, update: callUpdate) { error in
            if(error == nil) {
                self.configureAudioSession(data: data)
                let call = Call(uuid: uuid!, data: data)
                call.handle = data.handle
                self.callManager.addCall(call)
                self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_INCOMING, data.toJSON())
                self.endCallNotExist(data)
            }
            completion()
        }
    }
    
    
    @objc public func startCall(_ data: Data, fromPushKit: Bool) {
        // 🗑️ Removed self.data = data
        initCallkitProvider(data)
        
        guard let newUUID = UUID(uuidString: data.uuid) else { return }
        
        let newCall = Call(uuid: newUUID, data: data, isOutGoing: true)
        newCall.handle = data.handle
        self.callManager.addCall(newCall)
        
        // 기존 콜이 있으면 replace, 없으면 일반 start
        if let existingCall = self.outgoingCall ?? self.answerCall {
            self.outgoingCall = newCall
            self.callManager.replaceCall(oldCall: existingCall, newData: data)
        } else {
            self.outgoingCall = newCall
            self.callManager.startCall(data)
        }
    }
    
    @objc public func muteCall(_ callId: String, isMuted: Bool) {
        guard let callId = UUID(uuidString: callId),
              let call = self.callManager.callWithUUID(uuid: callId) else {
            return
        }
        if call.isMuted == isMuted {
            self.sendMuteEvent(callId.uuidString, isMuted)
        } else {
            self.callManager.muteCall(call: call, isMuted: isMuted)
        }
    }
    
    @objc public func holdCall(_ callId: String, onHold: Bool) {
        guard let callId = UUID(uuidString: callId),
              let call = self.callManager.callWithUUID(uuid: callId) else {
            return
        }
        if call.isOnHold == onHold {
            self.sendMuteEvent(callId.uuidString,  onHold)
        } else {
            self.callManager.holdCall(call: call, onHold: onHold)
        }
    }
    
    @objc public func endCall(_ data: Data) {
        // ✅ Logic changed: Find the call by UUID instead of relying on self.data or isFromPushKit
        if let uuid = UUID(uuidString: data.uuid), let call = self.callManager.callWithUUID(uuid: uuid) {
             self.callManager.endCall(call: call)
             // Note: Events are triggered in the provider delegate
        } else {
             // If call doesn't exist in manager, try to clean up "dangling" calls or just ignore
             // Maybe it was already ended.
             let call = Call(uuid: UUID(uuidString: data.uuid)!, data: data)
             self.callManager.endCall(call: call)
        }
    }
    
    @objc public func connectedCall(_ data: Data) {
         // ✅ Logic changed: Find call by UUID
         if let uuid = UUID(uuidString: data.uuid), let call = self.callManager.callWithUUID(uuid: uuid) {
             self.callManager.connectedCall(call: call)
         }
    }
    
    @objc public func activeCalls() -> [[String: Any]] {
        return self.callManager.activeCalls()
    }
    
    @objc public func endAllCalls() {
        self.callManager.endCallAlls()
    }
    
    public func saveEndCall(_ uuid: String, _ reason: Int) {
        switch reason {
        case 1:
            self.sharedProvider?.reportCall(with: UUID(uuidString: uuid)!, endedAt: Date(), reason: CXCallEndedReason.failed)
            break
        case 2, 6:
            self.sharedProvider?.reportCall(with: UUID(uuidString: uuid)!, endedAt: Date(), reason: CXCallEndedReason.remoteEnded)
            break
        case 3:
            self.sharedProvider?.reportCall(with: UUID(uuidString: uuid)!, endedAt: Date(), reason: CXCallEndedReason.unanswered)
            break
        case 4:
            self.sharedProvider?.reportCall(with: UUID(uuidString: uuid)!, endedAt: Date(), reason: CXCallEndedReason.answeredElsewhere)
            break
        case 5:
            self.sharedProvider?.reportCall(with: UUID(uuidString: uuid)!, endedAt: Date(), reason: CXCallEndedReason.declinedElsewhere)
            break
        default:
            break
        }
    }
    
    
    func endCallNotExist(_ data: Data) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(data.duration)) {
            // ✅ Logic changed: Use local data, lookup call by UUID
            if let uuid = UUID(uuidString: data.uuid),
               let call = self.callManager.callWithUUID(uuid: uuid) {
                
                // If call exists and is NOT answered and NOT outgoing, timeout.
                if self.answerCall == nil && self.outgoingCall == nil {
                    self.callEndTimeout(data)
                }
            }
        }
    }
    
    
    
    func callEndTimeout(_ data: Data) {
        self.saveEndCall(data.uuid, 3)
        guard let call = self.callManager.callWithUUID(uuid: UUID(uuidString: data.uuid)!) else {
            return
        }
        self.showMissedCallNotification(data)
        sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TIMEOUT, data.toJSON())
        if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
            appDelegate.onTimeOut(call)
        }
    }
    
    func getHandleType(_ handleType: String?) -> CXHandle.HandleType {
        var typeDefault = CXHandle.HandleType.generic
        switch handleType {
        case "number":
            typeDefault = CXHandle.HandleType.phoneNumber
            break
        case "email":
            typeDefault = CXHandle.HandleType.emailAddress
        default:
            typeDefault = CXHandle.HandleType.generic
        }
        return typeDefault
    }
    
    func initCallkitProvider(_ data: Data) {
        if(self.sharedProvider == nil){
            self.sharedProvider = CXProvider(configuration: createConfiguration(data))
            self.sharedProvider?.setDelegate(self, queue: nil)
        }
        self.callManager.setSharedProvider(self.sharedProvider!)
    }
    
    func createConfiguration(_ data: Data) -> CXProviderConfiguration {
        let configuration = CXProviderConfiguration(localizedName: data.appName)
        configuration.supportsVideo = data.supportsVideo
        configuration.maximumCallGroups = data.maximumCallGroups
        configuration.maximumCallsPerCallGroup = data.maximumCallsPerCallGroup
        
        configuration.supportedHandleTypes = [
            CXHandle.HandleType.generic,
            CXHandle.HandleType.emailAddress,
            CXHandle.HandleType.phoneNumber
        ]
        if #available(iOS 11.0, *) {
            configuration.includesCallsInRecents = data.includesCallsInRecents
        }
        if !data.iconName.isEmpty {
            if let image = UIImage(named: data.iconName) {
                configuration.iconTemplateImageData = image.pngData()
            } else {
                print("Unable to load icon \(data.iconName).");
            }
        }
        if !data.ringtonePath.isEmpty || data.ringtonePath != "system_ringtone_default"  {
            configuration.ringtoneSound = data.ringtonePath
        }
        return configuration
    }
    
    func sendDefaultAudioInterruptionNotificationToStartAudioResource(){
        var userInfo : [AnyHashable : Any] = [:]
        let intrepEndeRaw = AVAudioSession.InterruptionType.ended.rawValue
        userInfo[AVAudioSessionInterruptionTypeKey] = intrepEndeRaw
        userInfo[AVAudioSessionInterruptionOptionKey] = AVAudioSession.InterruptionOptions.shouldResume.rawValue
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: self, userInfo: userInfo)
    }
    
    func configureAudioSession(data: Data?){
        // ✅ Changed: accept Data as argument
        if data?.configureAudioSession != false {
            let session = AVAudioSession.sharedInstance()
            do{
                try session.setCategory(AVAudioSession.Category.playAndRecord, options: [
                    .allowBluetoothA2DP,
                    .duckOthers,
                    .allowBluetooth,
                ])
                
                try session.setMode(self.getAudioSessionMode(data?.audioSessionMode))
                try session.setActive(data?.audioSessionActive ?? true)
                try session.setPreferredSampleRate(data?.audioSessionPreferredSampleRate ?? 44100.0)
                try session.setPreferredIOBufferDuration(data?.audioSessionPreferredIOBufferDuration ?? 0.005)
            }catch{
                print(error)
            }
        }
    }
    
    func getAudioSessionMode(_ audioSessionMode: String?) -> AVAudioSession.Mode {
        var mode = AVAudioSession.Mode.default
        switch audioSessionMode {
        case "gameChat":
            mode = AVAudioSession.Mode.gameChat
            break
        case "measurement":
            mode = AVAudioSession.Mode.measurement
            break
        case "moviePlayback":
            mode = AVAudioSession.Mode.moviePlayback
            break
        case "spokenAudio":
            mode = AVAudioSession.Mode.spokenAudio
            break
        case "videoChat":
            mode = AVAudioSession.Mode.videoChat
            break
        case "videoRecording":
            mode = AVAudioSession.Mode.videoRecording
            break
        case "voiceChat":
            mode = AVAudioSession.Mode.voiceChat
            break
        case "voicePrompt":
            if #available(iOS 12.0, *) {
                mode = AVAudioSession.Mode.voicePrompt
            } else {
                // Fallback on earlier versions
            }
            break
        default:
            mode = AVAudioSession.Mode.default
        }
        return mode
    }
    
    public func providerDidReset(_ provider: CXProvider) {
        for call in self.callManager.calls {
            call.endCall()
        }
        self.callManager.removeAllCalls()
    }
    
    public func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        // ✅ Logic changed: Retrieve the call we added in startCall() instead of using self.data
        // Note: The call must have been added to callManager before this action fires.
        guard let call = self.callManager.callWithUUID(uuid: action.callUUID) else {
            print("Error: Call not found for UUID: \(action.callUUID)")
            action.fail()
            return
        }
        
        configureAudioSession(data: call.data)
        
        call.hasStartedConnectDidChange = { [weak self] in
            self?.sharedProvider?.reportOutgoingCall(with: call.uuid, startedConnectingAt: call.connectData)
        }
        call.hasConnectDidChange = { [weak self] in
            self?.sharedProvider?.reportOutgoingCall(with: call.uuid, connectedAt: call.connectedData)
        }
        
        // Ensure outgoingCall reference is correct (should have been set in startCall but safe to re-set)
        self.outgoingCall = call;
        
        action.fulfill()
        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_START, call.data.toJSON())
        
    }
    
    public func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard let call = self.callManager.callWithUUID(uuid: action.callUUID) else{
            action.fail()
            return
        }
        
        // ✅ Use call.data
        self.configureAudioSession(data: call.data)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1200)) {
            self.configureAudioSession(data: call.data)
        }


        call.hasConnectDidChange = { [weak self] in
            self?.sharedProvider?.reportOutgoingCall(with: call.uuid, connectedAt: call.connectedData)
        }
        call.data.isAccepted = true
        self.answerCall = call
        action.fulfill()
        sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_ACCEPT, call.data.toJSON())
        if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
            appDelegate.onAccept(call, action)
        }
    }
    
    
    public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        guard let call = self.callManager.callWithUUID(uuid: action.callUUID) else {
            // If call is not in manager, we can't get specific data, send generic timeout or handled externally
            // But since we strictly manage calls, this case should only happen if already removed.
            if(self.answerCall == nil && self.outgoingCall == nil){
                // Try to use a placeholder data if absolutely needed, but better to fail gracefully
            } 
            action.fail()
            return
        }
        
        call.endCall()
        
        // ✅ Logic: Identify if the ending call is the active one
        let isAnsweredCall = (self.answerCall?.uuid.uuidString == call.uuid.uuidString)
        let isOutgoingCall = (self.outgoingCall?.uuid.uuidString == call.uuid.uuidString)
        
        self.callManager.removeCall(call)
        
        // If it's not an active call (e.g. incoming call rejected while another is active)
        if !isAnsweredCall && !isOutgoingCall {
            action.fulfill()
            sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_DECLINE, call.data.toJSON())
            if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
                appDelegate.onDecline(call, action)
            } 
        } else {
            // If it WAS the active call, clear the reference
            if isAnsweredCall {
                self.answerCall = nil
            }
            if isOutgoingCall {
                self.outgoingCall = nil
            }
            action.fulfill()
            sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_ENDED, call.data.toJSON())
            if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
                appDelegate.onEnd(call, action)
            } 
        }
    }
    
    
    public func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        print("CXSetHeldCallAction action isOnHold : \(action.isOnHold)")
        guard let call = self.callManager.callWithUUID(uuid: action.callUUID) else {
            action.fail()
            return
        }
        call.isOnHold = action.isOnHold
        call.isMuted = action.isOnHold
        self.callManager.setHold(call: call, onHold: action.isOnHold)
        action.fulfill()
        sendHoldEvent(action.callUUID.uuidString, action.isOnHold)
        

        // hold 해제 시 오디오 세션 복구
        if !action.isOnHold {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.sendDefaultAudioInterruptionNotificationToStartAudioResource()
            }
        }
    }
    
    public func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        guard let call = self.callManager.callWithUUID(uuid: action.callUUID) else {
            action.fail()
            return
        }
        call.isMuted = action.isMuted
        action.fulfill()
        sendMuteEvent(action.callUUID.uuidString, action.isMuted)
        
    }
    
    public func provider(_ provider: CXProvider, perform action: CXSetGroupCallAction) {
        guard (self.callManager.callWithUUID(uuid: action.callUUID)) != nil else {
            action.fail()
            return
        }
        action.fulfill()
        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TOGGLE_GROUP, [ "id": action.callUUID.uuidString, "callUUIDToGroupWith" : action.callUUIDToGroupWith?.uuidString])
        
    }
    
    public func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        guard (self.callManager.callWithUUID(uuid: action.callUUID)) != nil else {
            action.fail()
            return
        }
        action.fulfill()
        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TOGGLE_DMTF, [ "id": action.callUUID.uuidString, "digits": action.digits, "type": action.type.rawValue ])
        
    }
    
    
    public func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        guard let call = self.callManager.callWithUUID(uuid: action.uuid) else {
            action.fail()
            return
        }
        
        if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
            appDelegate.onTimeOut(call)
        }
        action.fulfill()
        // ✅ Use call.data
        sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TIMEOUT, call.data.toJSON())
    }
    
    public func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {

        if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
            appDelegate.didActivateAudioSession(audioSession)
        }

        if(self.answerCall?.hasConnected ?? false){
            sendDefaultAudioInterruptionNotificationToStartAudioResource()
            return
        }
        if(self.outgoingCall?.hasConnected ?? false){
            sendDefaultAudioInterruptionNotificationToStartAudioResource()
            return
        }
        self.outgoingCall?.startCall(withAudioSession: audioSession) {success in
            if success {
                self.outgoingCall?.startAudio()
            }
        }
        self.answerCall?.ansCall(withAudioSession: audioSession) { success in
            if success{
                self.answerCall?.startAudio()
            }
        }
        sendDefaultAudioInterruptionNotificationToStartAudioResource()
        
        // ✅ Configure based on active call data if available
        if let data = self.answerCall?.data ?? self.outgoingCall?.data {
            configureAudioSession(data: data)
        } else {
             // Fallback if no active call (shouldn't happen in didActivate)
             // configureAudioSession(data: nil) 
        }

        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TOGGLE_AUDIO_SESSION, [ "isActivate": true ])
    }
    
    public func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        // ... (No changes needed here as it doesn't use self.data)
        if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
            appDelegate.didDeactivateAudioSession(audioSession)
        }

        if self.outgoingCall?.isOnHold ?? false || self.answerCall?.isOnHold ?? false{
            print("Call is on hold")
            return
        }
        
        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TOGGLE_AUDIO_SESSION, [ "isActivate": false ])
    }
    
    // ... (Rest of helper methods like sendMuteEvent remain the same) ...
    
    // Helper methods to match existing file structure
    private func sendMuteEvent(_ id: String, _ isMuted: Bool) {
        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TOGGLE_MUTE, [ "id": id, "isMuted": isMuted ])
    }
    
    private func sendHoldEvent(_ id: String, _ isOnHold: Bool) {
        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TOGGLE_HOLD, [ "id": id, "isOnHold": isOnHold ])
    }
    
    @objc public func sendCallbackEvent(_ data: [String: Any]?) {
        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_CALLBACK, data)
    }
    
    private func requestNotificationPermission(_ map: [String: Any]) {
        CallkitNotificationManager.shared.requestNotificationPermission(map)
    }
    
    private func showMissedCallNotification(_ data: Data) {
        if(!data.isShowMissedCallNotification){
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "\(data.nameCaller)"
        content.body = "\(data.missedNotificationSubtitle)"
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = "MISSED_CALL_CATEGORY"
        content.userInfo = data.toJSON()

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

        let request = UNNotificationRequest(
            identifier: data.uuid,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling missed call notification: \(error)")
            } else {
                print("Missed call notification scheduled.")
            }
        }
    }
}

class EventCallbackHandler: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private var queuedEvents: [[String: Any]] = []
    public func send(_ event: String, _ body: Any) {
        let data: [String : Any] = [
            "event": event,
            "body": body
        ]
        if let sink = eventSink {
            sink(data)
        } else {
            queuedEvents.append(data)
        }
    }
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        for event in queuedEvents {
            self.eventSink?(event)
        }
        queuedEvents.removeAll()
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
