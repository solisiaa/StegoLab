import SwiftUI
import AppKit

@main
struct StegoLabApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 620)
                .onAppear {
                    // При запуске через `swift run` процесс стартует как фоновая
                    // утилита и фокус остается у Терминала — поэтому ввод падает
                    // в консоль. Переводим в обычный GUI-режим и забираем фокус.
                    DispatchQueue.main.async {
                        NSApplication.shared.setActivationPolicy(.regular)
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        if let window = NSApplication.shared.windows.first {
                            window.makeKeyAndOrderFront(nil)
                            window.becomeKey()
                        }
                    }
                }
        }
        .windowResizability(.contentSize)
    }
}
