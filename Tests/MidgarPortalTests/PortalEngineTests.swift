import XCTest
@testable import MidgarPortal

final class HexLatticeTests: XCTestCase {
    func testRingsHaveSixTimesRadiusCellsAtThatDistance() {
        for radius in 1...5 {
            let ring = HexLattice.ring(radius)
            XCTAssertEqual(ring.count, 6 * radius)
            XCTAssertEqual(Set(ring).count, ring.count)
            XCTAssertTrue(ring.allSatisfy { $0.ringIndex == radius })
        }
        XCTAssertEqual(HexLattice.ring(0), [.origin])
    }

    func testSpiralIsOrderedByDistanceAndComplete() {
        let spiral = HexLattice.spiral(rings: 3)
        XCTAssertEqual(spiral.count, HexLattice.cellCount(rings: 3))
        XCTAssertEqual(Set(spiral).count, spiral.count)
        XCTAssertEqual(spiral.map(\.ringIndex), spiral.map(\.ringIndex).sorted())
    }

    func testRingsNeededMatchesCapacity() {
        XCTAssertEqual(HexLattice.ringsNeeded(forCells: 1), 0)
        XCTAssertEqual(HexLattice.ringsNeeded(forCells: 7), 1)
        XCTAssertEqual(HexLattice.ringsNeeded(forCells: 8), 2)
        XCTAssertEqual(HexLattice.ringsNeeded(forCells: 19), 2)
        XCTAssertEqual(HexLattice.ringsNeeded(forCells: 20), 3)
    }

    func testNeighbouringCellsAreExactlyOnePitchApart() {
        let origin = HexLattice.worldPoint(of: .origin, pitch: 100)
        for direction in HexCoordinate.directions {
            let point = HexLattice.worldPoint(of: direction, pitch: 100)
            XCTAssertEqual(hypot(point.x - origin.x, point.y - origin.y), 100, accuracy: 0.001)
        }
    }

    func testEvenSpacingSpreadsGapsAroundTheRing() {
        let ring = HexLattice.ring(2)
        let used = HexLattice.evenlySpaced(ring, count: 10)
        XCTAssertEqual(used.count, 10)
        XCTAssertEqual(Set(used).count, 10)
        XCTAssertEqual(HexLattice.evenlySpaced(ring, count: 12), ring)
        XCTAssertEqual(HexLattice.evenlySpaced(ring, count: 0), [])
    }
}

final class PortalLayoutTests: XCTestCase {
    private let ids = (1...16).map(String.init)

    func testCoreSitsAtTheOriginAndEveryAppGetsACell() {
        let layout = PortalLayout.make(appIDs: ids, pitch: 100)
        XCTAssertTrue(layout.core.isCore)
        XCTAssertEqual(layout.core.world, .zero)
        XCTAssertEqual(layout.cells.count, 17)
        XCTAssertEqual(layout.cells.compactMap(\.appID), ids.sorted { Int($0)! < Int($1)! })
    }

    func testBestRankedAppsTakeTheInnerRing() {
        let layout = PortalLayout.make(appIDs: ids, pitch: 100)
        let inner = layout.cells.filter { $0.hex.ringIndex == 1 }.compactMap(\.appID)
        XCTAssertEqual(Set(inner), Set(ids.prefix(6)))
    }

    func testCellsAndGhostsNeverShareAPosition() {
        let layout = PortalLayout.make(appIDs: ids, pitch: 100)
        let cellPoints = layout.cells.map(\.world)
        for ghost in layout.ghosts {
            XCTAssertFalse(cellPoints.contains { hypot($0.x - ghost.x, $0.y - ghost.y) < 1 })
        }
        XCTAssertGreaterThan(layout.ghosts.count, 10)
    }

    func testEmptyCatalogStillHasACore() {
        let layout = PortalLayout.make(appIDs: [], pitch: 100)
        XCTAssertEqual(layout.cells.count, 1)
        XCTAssertEqual(layout.reach, 0)
    }

    func testLargeCatalogsGrowOutwardWithoutOverlap() {
        let many = (1...60).map(String.init)
        let layout = PortalLayout.make(appIDs: many, pitch: 100)
        XCTAssertEqual(layout.cells.count, 61)
        XCTAssertEqual(Set(layout.cells.map(\.hex)).count, 61)
    }

    func testNeighbourSearchFollowsTheDirectionAndFindsNothingPastTheEdge() throws {
        let layout = PortalLayout.make(appIDs: ids, pitch: 100)
        let right = try XCTUnwrap(layout.neighbor(of: layout.core, toward: CGVector(dx: 1, dy: 0)))
        XCTAssertGreaterThan(right.world.x, 0)
        XCTAssertNil(layout.neighbor(of: layout.core, toward: .zero))
        let farthest = layout.cells.max { hypot($0.world.x, $0.world.y) < hypot($1.world.x, $1.world.y) }!
        let outward = CGVector(dx: farthest.world.x, dy: farthest.world.y)
        XCTAssertNil(layout.neighbor(of: farthest, toward: outward))
    }

    func testNearestCellPicksTheClosestWorldPoint() {
        let layout = PortalLayout.make(appIDs: ids, pitch: 100)
        let target = layout.cells[5]
        let nudged = CGPoint(x: target.world.x + 8, y: target.world.y - 6)
        XCTAssertEqual(layout.nearestCell(to: nudged), target)
    }
}

final class PortalLensTests: XCTestCase {
    private let lens = PortalLens(halfExtent: CGSize(width: 200, height: 300))

    func testTheCentreIsUntouched() {
        let projection = lens.project(.zero)
        XCTAssertEqual(projection.point, .zero)
        XCTAssertEqual(projection.scale, 1)
    }

    func testNearTheCentreMovementIsOneToOne() {
        let projection = lens.project(CGPoint(x: 4, y: 0))
        XCTAssertEqual(projection.point.x, 4, accuracy: 0.2)
    }

    func testScaleShrinksMonotonicallyAndStopsAtTheFloor() {
        var previous: CGFloat = 1
        for step in 0...40 {
            let scale = lens.project(CGPoint(x: CGFloat(step) * 30, y: 0)).scale
            XCTAssertLessThanOrEqual(scale, previous + 0.000_001)
            XCTAssertGreaterThanOrEqual(scale, lens.minimumScale)
            previous = scale
        }
    }

    func testCompressionNeverReordersCells() {
        var previous: CGFloat = -1
        for step in 0...60 {
            let x = lens.project(CGPoint(x: CGFloat(step) * 20, y: 0)).point.x
            XCTAssertGreaterThan(x, previous)
            previous = x
        }
    }

    func testFarCellsSitInsideTheViewportEllipse() {
        let projection = lens.project(CGPoint(x: 5000, y: 5000))
        XCTAssertLessThan(abs(projection.point.x), 200 * 1.2)
        XCTAssertLessThan(abs(projection.point.y), 300 * 1.2)
    }

    func testDegenerateViewportsDoNotDivideByZero() {
        let flat = PortalLens(halfExtent: .zero)
        XCTAssertEqual(flat.project(CGPoint(x: 10, y: 10)).scale, 1)
    }
}

final class PortalCameraTests: XCTestCase {
    private let snaps = [CGPoint.zero, CGPoint(x: 100, y: 0), CGPoint(x: 0, y: 100), CGPoint(x: -100, y: 0)]

    private func settle(_ camera: inout PortalCamera, limit: Int = 600) -> Int {
        var frames = 0
        while camera.isMoving && frames < limit {
            camera.step(1.0 / 60.0)
            frames += 1
        }
        return frames
    }

    func testDragFollowsTheFingerOppositeToTheWorld() {
        var camera = PortalCamera(bound: 500)
        camera.beginDrag()
        camera.drag(translation: CGPoint(x: 30, y: -20))
        XCTAssertEqual(camera.position.x, -30, accuracy: 0.001)
        XCTAssertEqual(camera.position.y, 20, accuracy: 0.001)
    }

    func testDraggingPastTheEdgeIsResisted() {
        var camera = PortalCamera(bound: 100)
        camera.beginDrag()
        camera.drag(translation: CGPoint(x: -400, y: 0))
        let reached = hypot(camera.position.x, camera.position.y)
        XCTAssertGreaterThan(reached, 100)
        XCTAssertLessThan(reached, 300)
    }

    func testSlowReleaseSnapsToTheNearestCell() {
        var camera = PortalCamera(bound: 500)
        camera.beginDrag()
        camera.drag(translation: CGPoint(x: -70, y: 0))
        camera.endDrag(velocity: .zero, snapPoints: snaps)
        XCTAssertLessThan(settle(&camera), 600)
        XCTAssertEqual(camera.position, CGPoint(x: 100, y: 0))
        XCTAssertFalse(camera.isMoving)
    }

    func testAFlickCoastsToTheCellItWouldHaveReached() {
        var camera = PortalCamera(bound: 500)
        camera.beginDrag()
        camera.drag(translation: CGPoint(x: -10, y: 0))
        camera.endDrag(velocity: CGPoint(x: -700, y: 0), snapPoints: snaps)
        _ = settle(&camera)
        XCTAssertEqual(camera.position, CGPoint(x: 100, y: 0))
    }

    func testTheSpringNeverOvershootsItsTarget() {
        var camera = PortalCamera(position: CGPoint(x: 0, y: 0), bound: 500)
        camera.glide(to: CGPoint(x: 100, y: 0), initialVelocity: CGPoint(x: 5000, y: 0))
        var peak: CGFloat = 0
        while camera.isMoving {
            camera.step(1.0 / 120.0)
            peak = max(peak, camera.position.x)
        }
        XCTAssertLessThanOrEqual(peak, 100.5)
    }

    func testGlidingToWhereWeAlreadyAreRestsImmediately() {
        var camera = PortalCamera(position: CGPoint(x: 20, y: 20), bound: 500)
        camera.glide(to: CGPoint(x: 20, y: 20))
        XCTAssertFalse(camera.isMoving)
    }

    func testHugeFrameGapsAreClampedInsteadOfExploding() {
        var camera = PortalCamera(bound: 500)
        camera.glide(to: CGPoint(x: 100, y: 100))
        camera.step(30)
        XCTAssertTrue(camera.position.x.isFinite && camera.position.y.isFinite)
        XCTAssertLessThanOrEqual(hypot(camera.position.x, camera.position.y), 142)
    }

    func testScrollSequencesSettleOnACell() {
        var camera = PortalCamera(bound: 500)
        camera.nudge(by: CGPoint(x: -30, y: 0))
        camera.nudge(by: CGPoint(x: -30, y: 0))
        camera.settle(snapPoints: snaps)
        _ = settle(&camera)
        XCTAssertEqual(camera.position, CGPoint(x: 100, y: 0))
    }

    func testDragMovesAreIgnoredWithoutADragSession() {
        var camera = PortalCamera(bound: 500)
        camera.drag(translation: CGPoint(x: 50, y: 50))
        XCTAssertEqual(camera.position, .zero)
    }
}

final class PortalRankingTests: XCTestCase {
    private func app(_ name: String, topics: [String] = [], related: [String] = [], value: Double = 0.5,
                     featured: Bool = false, order: Int = 0, family: String? = nil) -> MidgarApp {
        MidgarApp(
            appId: name, bundleId: "com.example.\(name)", name: name, featured: featured, order: order,
            topics: topics, related: related, family: family, value: value
        )
    }

    func testRelatedAndSharedTopicAppsComeFirst() {
        let host = app("host", topics: ["music"], related: ["com.example.pal"])
        let pal = app("pal")
        let sameTopic = app("topic", topics: ["music"])
        let stranger = app("stranger", value: 0.6)
        let ranked = PortalRanking.order(apps: [stranger, sameTopic, pal, host], hostBundleID: host.bundleId, installed: [])
        XCTAssertEqual(ranked.map(\.appId), ["pal", "topic", "stranger", "host"])
    }

    func testRelationCountsInEitherDirection() {
        let host = app("host")
        let pal = app("pal", related: ["com.example.host"])
        let other = app("other", value: 0.9)
        let ranked = PortalRanking.order(apps: [other, pal, host], hostBundleID: host.bundleId, installed: [])
        XCTAssertEqual(ranked.first?.appId, "pal")
    }

    func testInstalledAppsMoveOutwardAndTheHostGoesLast() {
        let host = app("host")
        let owned = app("owned", value: 1)
        let fresh = app("fresh", value: 0.4)
        let ranked = PortalRanking.order(apps: [owned, fresh, host], hostBundleID: host.bundleId, installed: ["com.example.owned"])
        XCTAssertEqual(ranked.map(\.appId), ["fresh", "owned", "host"])
    }

    func testValueFeaturedAndFamilyBreakTies() {
        let host = app("host", family: "f")
        let sibling = app("sibling", family: "f")
        let big = app("big", value: 1)
        let star = app("star", value: 0.5, featured: true)
        let plain = app("plain")
        let ranked = PortalRanking.order(apps: [plain, star, big, sibling, host], hostBundleID: host.bundleId, installed: [])
        XCTAssertEqual(ranked.map(\.appId), ["sibling", "big", "star", "plain", "host"])
    }

    func testUnknownHostKeepsEveryApp() {
        let apps = [app("a"), app("b", value: 0.9)]
        let ranked = PortalRanking.order(apps: apps, hostBundleID: "com.unknown.app", installed: [])
        XCTAssertEqual(ranked.map(\.appId), ["b", "a"])
    }

    func testBundledCatalogPairsItsRelatedApps() {
        let apps = CatalogService.bundledApps()
        let psybeam = apps.first { $0.bundleId == "com.guitaripod.psybeam" }!
        let ranked = PortalRanking.order(apps: apps, hostBundleID: psybeam.bundleId, installed: [])
        XCTAssertEqual(ranked.first?.bundleId, "com.marcusziade.doublekick")
        XCTAssertEqual(ranked.last?.bundleId, psybeam.bundleId)
    }
}

@MainActor
final class PortalControllerTests: XCTestCase {
    private func makeController() -> PortalController {
        let controller = PortalController(scale: 2, reduceMotion: false)
        let apps = CatalogService.bundledApps()
        let ranked = PortalRanking.order(apps: apps, hostBundleID: "com.guitaripod.psybeam", installed: [])
        controller.load(ranked: ranked, hostBundleID: "com.guitaripod.psybeam", installed: [], initialFocus: ranked.first?.appId)
        controller.resize(to: CGSize(width: 393, height: 852), insets: PortalInsets(top: 110, bottom: 200))
        return controller
    }

    private func run(_ controller: PortalController, from start: CFTimeInterval, seconds: Double) -> CFTimeInterval {
        var time = start
        let end = start + seconds
        while time < end {
            time += 1.0 / 60.0
            controller.tick(now: time)
        }
        return time
    }

    func testOpeningDriftsToTheMostRelevantAppAndSettles() {
        let controller = makeController()
        var focused: PortalCell?
        controller.onFocusChange = { focused = $0 }
        var frameRequests: [Bool] = []
        controller.onNeedsFrames = { frameRequests.append($0) }
        controller.begin(at: 0)
        _ = run(controller, from: 0, seconds: 3)
        XCTAssertEqual(controller.focusedCell.appID, focused?.appID)
        XCTAssertFalse(controller.focusedCell.isCore)
        XCTAssertEqual(frameRequests.last, false)
        XCTAssertFalse(controller.camera.isMoving)
        XCTAssertEqual(controller.camera.position, controller.focusedCell.world)
    }

    func testTappingAnotherIconCentresItBeforeActivating() throws {
        let controller = makeController()
        controller.begin(at: 0)
        var time = run(controller, from: 0, seconds: 3)
        var activated: [PortalCell] = []
        controller.onActivate = { activated.append($0) }

        let other = try XCTUnwrap(controller.layout.cells.first { $0.index != controller.focusedIndex && !$0.isCore })
        let frame = try XCTUnwrap(controller.frame(forCell: other.index))
        controller.tap(at: frame.center)
        XCTAssertEqual(controller.focusedIndex, other.index)
        XCTAssertTrue(activated.isEmpty)
        time = run(controller, from: time, seconds: 1.5)

        let centred = try XCTUnwrap(controller.frame(forCell: other.index))
        controller.tap(at: centred.center)
        XCTAssertEqual(activated.map(\.index), [other.index])
    }

    func testDraggingChangesFocusAndSettlesOnACell() {
        let controller = makeController()
        controller.begin(at: 0)
        var time = run(controller, from: 0, seconds: 3)
        var focusChanges = 0
        controller.onFocusChange = { _ in focusChanges += 1 }
        controller.pointerBegan()
        controller.pointerMoved(translation: CGPoint(x: -140, y: 60))
        time = run(controller, from: time, seconds: 0.2)
        controller.pointerEnded(velocity: CGPoint(x: -400, y: 100))
        _ = run(controller, from: time, seconds: 3)
        XCTAssertGreaterThan(focusChanges, 0)
        XCTAssertEqual(controller.camera.position, controller.focusedCell.world)
    }

    func testEveryAppIsReportedSeenOnceWhenTheIntroEnds() {
        let controller = makeController()
        var seen: [String] = []
        controller.onSeen = { seen.append($0) }
        controller.begin(at: 0)
        _ = run(controller, from: 0, seconds: 4)
        XCTAssertEqual(seen.count, Set(seen).count)
        XCTAssertGreaterThanOrEqual(seen.count, 6)
        XCTAssertLessThanOrEqual(seen.count, 16)
    }

    func testKeyboardNavigationWalksToANeighbour() {
        let controller = makeController()
        controller.begin(at: 0)
        let time = run(controller, from: 0, seconds: 3)
        let before = controller.focusedIndex
        controller.moveFocus(toward: CGVector(dx: -1, dy: 0))
        _ = run(controller, from: time, seconds: 1.5)
        XCTAssertNotEqual(controller.focusedIndex, before)
    }

    func testReduceMotionOpensStraightOnTheFocusedApp() {
        let controller = PortalController(scale: 2, reduceMotion: true)
        let apps = CatalogService.bundledApps()
        controller.load(ranked: apps, hostBundleID: nil, installed: [], initialFocus: apps.first?.appId)
        controller.resize(to: CGSize(width: 393, height: 852), insets: PortalInsets(top: 110, bottom: 200))
        controller.begin(at: 0)
        controller.tick(now: 0.01)
        XCTAssertEqual(controller.focusedCell.appID, apps.first?.appId)
    }

    func testRotationKeepsTheFocusedApp() {
        let controller = makeController()
        controller.begin(at: 0)
        _ = run(controller, from: 0, seconds: 3)
        let app = controller.focusedCell.appID
        controller.resize(to: CGSize(width: 852, height: 393), insets: PortalInsets(top: 60, bottom: 160))
        XCTAssertEqual(controller.focusedCell.appID, app)
        XCTAssertEqual(controller.camera.position, controller.focusedCell.world)
    }

    func testRenderingTheFullPortalStaysWellInsideAFrameBudget() {
        let controller = makeController()
        controller.begin(at: 0)
        _ = run(controller, from: 0, seconds: 3)
        measure {
            for frame in 0..<120 {
                controller.renderer.render(camera: CGPoint(x: CGFloat(frame), y: CGFloat(frame) * 0.5), intro: 5)
            }
        }
    }

    func testAGrowingCatalogOfSixtyAppsStillLaysOutAndRenders() {
        let controller = PortalController(scale: 2, reduceMotion: false)
        let apps = (1...60).map { index in
            MidgarApp(
                appId: "\(index)", bundleId: "com.example.app\(index)", name: "App \(index)",
                accentHex: "#7C5CFF", topics: ["t\(index % 5)"], value: Double(index % 10) / 10
            )
        }
        let ranked = PortalRanking.order(apps: apps, hostBundleID: "com.example.app1", installed: [])
        controller.load(ranked: ranked, hostBundleID: "com.example.app1", installed: [], initialFocus: ranked.first?.appId)
        controller.resize(to: CGSize(width: 393, height: 852), insets: PortalInsets(top: 110, bottom: 200))
        XCTAssertEqual(controller.layout.cells.count, 61)
        XCTAssertEqual(Set(controller.layout.cells.map(\.hex)).count, 61)
        controller.begin(at: 0)
        var time: CFTimeInterval = 0
        while time < 4 {
            time += 1.0 / 60.0
            controller.tick(now: time)
        }
        XCTAssertFalse(controller.camera.isMoving)
        measure {
            for frame in 0..<120 {
                controller.renderer.render(camera: CGPoint(x: CGFloat(frame), y: CGFloat(frame) * 0.5), intro: 5)
            }
        }
    }
}
