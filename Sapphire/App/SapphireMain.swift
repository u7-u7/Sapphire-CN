import AppKit

/// 辅助进程直接进入最小运行循环，不能加载主界面或触发剪贴板/账户初始化。
@main
struct SapphireMain {
    @MainActor
    static func main() {
        if NotificationWindowRecovery.isAgentProcess {
            let app = NSApplication.shared
            app.setActivationPolicy(.prohibited)
            let delegate = NotificationRecoveryBootstrap()
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
            return
        }
        if URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent == "SapphireNotificationRecovery" { return }
        #if DEBUG && CN11_NOTIFICATION_DIAGNOSTICS
        if NotificationRealtimeDiagnostics.runIfRequested() { return }
        #endif
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}

@MainActor
private final class NotificationRecoveryBootstrap: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = NotificationWindowRecovery.runAgentIfRequested()
    }
}
