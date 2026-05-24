import AVFoundation
import Observation

@Observable
@MainActor
final class AudioRouteService {
    private(set) var isHeadsetConnected = false
    var onHeadsetStatusChanged: ((Bool) -> Void)?

    init() {
        checkRoute()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(routeChanged),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func routeChanged(notification: Notification) {
        checkRoute()
    }

    private func checkRoute() {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
        let connected = outputs.contains { output in
            switch output.portType {
            case .headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .usbAudio:
                return true
            default:
                return false
            }
        }
        if connected != isHeadsetConnected {
            isHeadsetConnected = connected
            onHeadsetStatusChanged?(connected)
        }
    }
}
