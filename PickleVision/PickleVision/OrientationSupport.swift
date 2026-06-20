import SwiftUI
import UIKit

/// The interface-orientation mask the app currently allows. Screens set this
/// via `.lockOrientation(_:)`; `AppDelegate` reports it to UIKit. Default is
/// portrait (the app opens on the menus). Main-thread only.
enum AppOrientation {
    static var mask: UIInterfaceOrientationMask = .portrait
}

/// Reports the per-screen orientation mask to UIKit. Menus are portrait; the
/// camera and calibration screens force landscape (the phone is mounted
/// landscape behind the baseline).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppOrientation.mask
    }
}

/// Forces this screen's supported orientation while it is on screen. Re-applied
/// on every appearance (including when revealed by a navigation pop), so the
/// menus return to portrait when the landscape camera/calibration screens pop.
private struct OrientationLock: ViewModifier {
    let mask: UIInterfaceOrientationMask

    func body(content: Content) -> some View {
        content.onAppear(perform: apply)
    }

    private func apply() {
        AppOrientation.mask = mask
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

extension View {
    /// Pins this screen to an orientation. Menus use `.portrait`; the camera and
    /// calibration screens use `.landscape`.
    func lockOrientation(_ mask: UIInterfaceOrientationMask) -> some View {
        modifier(OrientationLock(mask: mask))
    }
}
