import SwiftUI

if CommandLine.arguments.contains("--selftest") {
    Task { @MainActor in
        let code = await SelfTest.run()
        exit(code)
    }
    RunLoop.main.run()
} else {
    PixyBarApp.main()
}
