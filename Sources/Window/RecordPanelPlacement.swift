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

    struct DragAlignment: Equatable {
        let screen: Screen
        let defaultFrame: CGRect
        let alignsCenter: Bool
        let alignsTop: Bool
        let releaseFrame: CGRect
    }

    /// Drag selection uses the raw window frame, with stable ties independent of opening preferences.
    static func dragScreen(containing frame: CGRect, in screens: [Screen], previousID: String?) -> Screen? {
        var candidates: [Screen] = []
        var largestArea: CGFloat = 0
        for screen in screens {
            let intersection = frame.intersection(screen.frame)
            guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { continue }
            let area = intersection.width * intersection.height
            if area > largestArea { candidates = [screen]; largestArea = area }
            else if area == largestArea { candidates.append(screen) }
        }
        return candidates.first { $0.id == previousID } ?? candidates.first
    }

    /// The caller supplies the existing size/bounds constraints without moving the actual window.
    /// Preview and release use this same calculation, in global AppKit points.
    static func dragAlignment(for frame: CGRect, on screen: Screen,
                              constrainedFrame: CGRect? = nil) -> DragAlignment {
        let freeFrame = constrainedFrame ?? frame
        let target = CGRect(origin: origin(for: freeFrame.size, on: screen, savedOffset: nil),
                            size: freeFrame.size)
        let alignsCenter = abs(frame.midX - target.midX) <= 8
        let alignsTop = abs(frame.maxY - target.maxY) <= 8
        var release = freeFrame
        if alignsCenter { release.origin.x = target.minX }
        if alignsTop { release.origin.y = target.minY }
        return DragAlignment(screen: screen, defaultFrame: target, alignsCenter: alignsCenter,
                             alignsTop: alignsTop, releaseFrame: release)
    }
}
