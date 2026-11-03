import CoreGraphics

public enum NotchGeometry {
    /// Width of the island on a display without a camera housing.
    public static let simulatedWidth: CGFloat = 190
    public static let minimumHeight: CGFloat = 24

    /// Size of the camera housing, or of a simulated one on displays without it.
    public static func notchSize(
        screenFrame: CGRect, safeAreaTop: CGFloat,
        auxiliaryLeftWidth: CGFloat?, auxiliaryRightWidth: CGFloat?, menuBarHeight: CGFloat
    ) -> CGSize {
        if safeAreaTop > 0, let left = auxiliaryLeftWidth, let right = auxiliaryRightWidth {
            let width = screenFrame.width - left - right
            if width > 0 { return CGSize(width: width, height: safeAreaTop) }
        }
        return CGSize(width: simulatedWidth, height: max(menuBarHeight, minimumHeight))
    }

    /// A frame of `size` hanging from the top edge of the screen, centred horizontally, on whole points.
    public static func panelFrame(size: CGSize, screenFrame: CGRect) -> CGRect {
        let x = (screenFrame.midX - size.width / 2).rounded()
        let y = (screenFrame.maxY - size.height).rounded()
        return CGRect(x: x, y: y, width: size.width.rounded(), height: size.height.rounded())
    }
}
