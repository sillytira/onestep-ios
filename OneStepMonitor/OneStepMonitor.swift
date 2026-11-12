import DeviceActivity

final class OneStepMonitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        ScreenTimeShared.reconcile()
    }
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        ScreenTimeShared.reconcile()
    }
}
