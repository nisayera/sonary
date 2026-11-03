import Testing
@testable import Mouse

struct SmoothScrollerTests {
    private func total(_ scroller: inout SmoothScroller, dt: Double, seconds: Double) -> Double {
        var sum = 0.0
        var t = 0.0
        while t < seconds {
            sum += scroller.step(dt: dt).dy
            t += dt
        }
        return sum
    }

    @Test func totalEqualsImpulse() {
        var scroller = SmoothScroller(smoothness: 0.5)
        scroller.add(deltaY: 30, deltaX: 0)
        let sum = total(&scroller, dt: 1.0 / 60, seconds: 3)
        #expect(abs(sum - 30) < 0.01)
        #expect(scroller.isIdle)
    }

    @Test func frameRateIndependent() {
        var slow = SmoothScroller(smoothness: 0.5)
        var fast = SmoothScroller(smoothness: 0.5)
        slow.add(deltaY: 30, deltaX: 0)
        fast.add(deltaY: 30, deltaX: 0)
        let a = total(&slow, dt: 1.0 / 60, seconds: 0.3)
        let b = total(&fast, dt: 1.0 / 120, seconds: 0.3)
        #expect(abs(a - b) / 30 < 0.01)
    }

    @Test func zeroSmoothnessIsImmediate() {
        var scroller = SmoothScroller(smoothness: 0)
        scroller.add(deltaY: 12, deltaX: 4)
        let step = scroller.step(dt: 1.0 / 60)
        #expect(step.dy == 12 && step.dx == 4)
        #expect(scroller.isIdle)
    }

    @Test func impulsesAccumulate() {
        var scroller = SmoothScroller(smoothness: 0.5)
        scroller.add(deltaY: 10, deltaX: 0)
        scroller.add(deltaY: 5, deltaX: 0)
        let sum = total(&scroller, dt: 1.0 / 60, seconds: 3)
        #expect(abs(sum - 15) < 0.01)
    }

    @Test func idleWhenEmpty() {
        var scroller = SmoothScroller(smoothness: 0.5)
        #expect(scroller.isIdle)
        let step = scroller.step(dt: 1.0 / 60)
        #expect(step.dy == 0 && step.dx == 0)
    }
}
