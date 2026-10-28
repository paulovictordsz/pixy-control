import SwiftUI

struct PixyBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // O app vive no NSStatusItem (AppDelegate). A cena abaixo só existe porque App exige uma.
        Settings { EmptyView() }
    }
}
