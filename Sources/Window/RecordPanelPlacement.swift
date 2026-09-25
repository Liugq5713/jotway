import AppKit

@MainActor
enum RecordPanelPlacement {
    struct Screen: Equatable {
        let id: String
        let frame: CGRect
        let visibleFrame: CGRect
    }

    static var screens: [Screen] { NSScreen.screens.map { snapshot($0) } }

    static func snapshot(_ screen: NSScreen) -> Screen {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let id: String
        if let displayID = number?.uint32Value {
            if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
               let string = CFUUIDCreateString(nil, uuid) as String? {
                id = string.lowercased()
            } else {
                id = String(displayID)
            }
        } else {
            id = "primary"
        }
        return Screen(id: id, frame: screen.frame, visibleFrame: screen.visibleFrame)
    }

    static func targetScreen(in screens: [Screen], cursor: CGPoint, followsCursor: Bool,
                             fallbackID: String? = nil) -> Screen? {
        let primary = screens.first { $0.frame.origin == .zero } ?? screens.first
        guard followsCursor else { return primary }
        // AppKit's cursor boundary includes the top pixel, unlike CGRect.contains.
        return screens.first { NSMouseInRect(cursor, $0.frame, false) }
            ?? screens.first { $0.id == fallbackID }
            ?? primary
    }

    static func origin(for size: CGSize, on screen: Screen, savedOffset: CGPoint?) -> CGPoint {
        let visible = screen.visibleFrame
        if let savedOffset, savedOffset.x.isFinite, savedOffset.y.isFinite {
            let top = CGPoint(x: visible.minX + savedOffset.x, y: visible.maxY - savedOffset.y)
            let handle = CGRect(x: top.x, y: top.y - min(44, size.height),
                                width: size.width, height: min(44, size.height))
            let shown = visible.intersection(handle)
            if !shown.isNull, shown.width >= 44, shown.height >= 44 {
                return CGPoint(x: top.x, y: top.y - size.height)
            }
        }
        let centeredX = visible.midX - size.width / 2
        let upperY = visible.maxY - visible.height * 0.18 - size.height
        return CGPoint(
            x: min(max(centeredX, visible.minX), max(visible.minX, visible.maxX - size.width)),
            y: min(max(upperY, visible.minY), max(visible.minY, visible.maxY - size.height))
        )
    }

    /// 拖动或断屏时按窗口与显示器的交集选屏，不重新读取鼠标或唤起偏好。
    static func screen(containing frame: CGRect, in screens: [Screen]) -> Screen? {
        screens.filter { $0.frame.intersects(frame) }.max {
            let left = $0.frame.intersection(frame), right = $1.frame.intersection(frame)
            return left.width * left.height < right.width * right.height
        }
    }

    static func offset(for frame: CGRect, on screen: Screen) -> CGPoint {
        CGPoint(x: frame.minX - screen.visibleFrame.minX,
                y: screen.visibleFrame.maxY - frame.maxY)
    }
}
