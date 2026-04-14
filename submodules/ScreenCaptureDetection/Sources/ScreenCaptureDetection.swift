import Foundation
import SwiftSignalKit
import UIKit

public enum ScreenCaptureEvent {
    case still
    case video
}

private final class ScreenRecordingObserver: NSObject {
    let f: (Bool) -> Void

    init(_ f: @escaping (Bool) -> Void) {
        self.f = f

        super.init()

        UIScreen.main.addObserver(self, forKeyPath: "captured", options: [.new], context: nil)
    }

    func clear() {
        UIScreen.main.removeObserver(self, forKeyPath: "captured")
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "captured" {
            if let value = change?[.newKey] as? Bool {
                self.f(value)
            }
        }
    }
}

private func screenRecordingActive() -> Signal<Bool, NoError> {
    return Signal { subscriber in
        if #available(iOSApplicationExtension 11.0, iOS 11.0, *) {
            subscriber.putNext(UIScreen.main.isCaptured)
            let observer = ScreenRecordingObserver({ value in
                subscriber.putNext(value)
            })
            return ActionDisposable {
                Queue.mainQueue().async {
                    observer.clear()
                }
            }
        } else {
            subscriber.putNext(false)
            return EmptyDisposable
        }
    } |> runOn(Queue.mainQueue())
}

public func screenCaptureEvents() -> Signal<ScreenCaptureEvent, NoError> {
    return Signal { subscriber in
        let observer = NotificationCenter.default.addObserver(forName: UIApplication.userDidTakeScreenshotNotification, object: nil, queue: .main, using: { _ in
            // 🛑 极客补丁 1：屏蔽截屏事件广播，已掏空闭包
        })

        let screenRecordingDisposable = screenRecordingActive().start(next: { value in
            // 🛑 极客补丁 2：屏蔽录屏事件广播，已掏空闭包
        })

        return ActionDisposable {
            Queue.mainQueue().async {
                NotificationCenter.default.removeObserver(observer)
                screenRecordingDisposable.dispose()
            }
        }
    }
    |> runOn(Queue.mainQueue())
}

public final class ScreenCaptureDetectionManager {
    private var observer: NSObjectProtocol?
    private var screenRecordingDisposable: Disposable?
    private var screenRecordingCheckTimer: SwiftSignalKit.Timer?

    public var isRecordingActive = false

    public init(check: @escaping () -> Bool) {
        self.observer = NotificationCenter.default.addObserver(forName: UIApplication.userDidTakeScreenshotNotification, object: nil, queue: .main, using: { _ in
            // 🛑 极客补丁 3：直接留空闭包，永远不去执行打小报告的 check()
        })

        self.screenRecordingDisposable = screenRecordingActive().start(next: { _ in
            // 🛑 极客补丁 4：彻底无视录屏状态变化，留空闭包
        })
    }

    deinit {
        if let observer = self.observer {
            NotificationCenter.default.removeObserver(observer)
        }
        self.screenRecordingDisposable?.dispose()
        self.screenRecordingCheckTimer?.invalidate()
        self.screenRecordingCheckTimer = nil
    }
}