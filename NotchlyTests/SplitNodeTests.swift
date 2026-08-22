import XCTest

@MainActor
final class SplitNodeTests: XCTestCase {

    private func leaf(_ dir: String = "/tmp") -> SplitNode {
        .pane(id: UUID(), workingDirectory: dir)
    }

    // MARK: - Splitting

    func testSplittingALeafProducesTwoPanes() {
        let root = leaf("/a")
        let (tree, newId) = root.splitting(root.id, direction: .horizontal)

        XCTAssertEqual(tree.allPaneIds.count, 2)
        XCTAssertEqual(tree.allPaneIds, [root.id, newId])
        XCTAssertFalse(tree.isLeaf)
        // The new pane inherits the working directory of the pane it split from.
        XCTAssertEqual(tree.workingDirectory(for: newId), "/a")
    }

    func testSplittingPlaceNewBeforePutsTheFreshPaneFirst() {
        let root = leaf()
        let (tree, newId) = root.splitting(root.id, direction: .vertical, placeNewBefore: true)

        XCTAssertEqual(tree.allPaneIds, [newId, root.id])
    }

    func testSplittingANestedPaneKeepsTheRestOfTheTreeIntact() {
        let root = leaf()
        let (twoPanes, second) = root.splitting(root.id, direction: .horizontal)
        let (threePanes, third) = twoPanes.splitting(second, direction: .vertical)

        XCTAssertEqual(threePanes.allPaneIds, [root.id, second, third])
        XCTAssertEqual(threePanes.id, twoPanes.id, "the outer split node must keep its identity")
    }

    func testSplittingAnUnknownPaneIsANoOp() {
        let root = leaf()
        let (tree, _) = root.splitting(UUID(), direction: .horizontal)

        XCTAssertEqual(tree, root)
    }

    // MARK: - Removing

    func testRemovingTheOnlyPaneReturnsNil() {
        let root = leaf()
        XCTAssertNil(root.removing(root.id))
    }

    func testRemovingCollapsesTheSplitIntoTheSurvivingPane() {
        let root = leaf()
        let (tree, newId) = root.splitting(root.id, direction: .horizontal)

        let survivor = tree.removing(newId)
        XCTAssertEqual(survivor, root, "removing one side must collapse the split, not leave an empty branch")
    }

    func testRemovingANestedPaneCollapsesOnlyTheInnerSplit() {
        let root = leaf()
        let (twoPanes, second) = root.splitting(root.id, direction: .horizontal)
        let (threePanes, third) = twoPanes.splitting(second, direction: .vertical)

        let remaining = threePanes.removing(third)
        XCTAssertEqual(remaining?.allPaneIds, [root.id, second])
        XCTAssertEqual(remaining?.id, twoPanes.id)
    }

    func testRemovingAnUnknownPaneIsANoOp() {
        let root = leaf()
        let (tree, _) = root.splitting(root.id, direction: .horizontal)

        XCTAssertEqual(tree.removing(UUID()), tree)
    }

    // MARK: - Working directories

    func testUpdatingWorkingDirectoryOnlyTouchesTheTargetPane() {
        let root = leaf("/a")
        let (tree, newId) = root.splitting(root.id, direction: .horizontal)

        let updated = tree.updatingWorkingDirectory(newId, to: "/b")
        XCTAssertEqual(updated.workingDirectory(for: newId), "/b")
        XCTAssertEqual(updated.workingDirectory(for: root.id), "/a")
    }

    func testWorkingDirectoryForUnknownPaneIsNil() {
        XCTAssertNil(leaf().workingDirectory(for: UUID()))
    }

    // MARK: - Ratios

    func testUpdatingRatioTargetsTheMatchingSplitOnly() {
        let root = leaf()
        let (twoPanes, second) = root.splitting(root.id, direction: .horizontal)
        let (threePanes, _) = twoPanes.splitting(second, direction: .vertical)

        let updated = threePanes.updatingRatio(threePanes.id, to: 0.25)
        guard case .split(_, _, _, let inner, let ratio) = updated else {
            return XCTFail("expected a split at the root")
        }
        XCTAssertEqual(ratio, 0.25)
        guard case .split(_, _, _, _, let innerRatio) = inner else {
            return XCTFail("expected the inner split to survive")
        }
        XCTAssertEqual(innerRatio, 0.5, "the untouched split keeps its ratio")
    }

    // MARK: - Cloning

    func testCloneKeepsShapeAndDirectoriesButRenewsEveryId() {
        let root = leaf("/a")
        let (twoPanes, second) = root.splitting(root.id, direction: .horizontal)
        let (original, _) = twoPanes.splitting(second, direction: .vertical)
        let copy = original.clonedWithFreshIds()

        XCTAssertEqual(copy.allPaneIds.count, original.allPaneIds.count)
        XCTAssertTrue(Set(copy.allPaneIds).isDisjoint(with: Set(original.allPaneIds)),
                      "a duplicated tab must not reuse pane ids — terminals are keyed by them")
        XCTAssertNotEqual(copy.id, original.id)
        for id in copy.allPaneIds {
            XCTAssertEqual(copy.workingDirectory(for: id), "/a")
        }
    }

    // MARK: - Navigation

    func testPaneNavigationWrapsInBothDirections() {
        let root = leaf()
        let (twoPanes, second) = root.splitting(root.id, direction: .horizontal)
        let (tree, third) = twoPanes.splitting(second, direction: .vertical)

        XCTAssertEqual(tree.nextPaneId(after: root.id), second)
        XCTAssertEqual(tree.nextPaneId(after: third), root.id)
        XCTAssertEqual(tree.previousPaneId(before: root.id), third)
        XCTAssertEqual(tree.previousPaneId(before: second), root.id)
    }

    func testNavigationFromAnUnknownPaneFallsBackToAnEdge() {
        let root = leaf()
        let (tree, second) = root.splitting(root.id, direction: .horizontal)

        XCTAssertEqual(tree.nextPaneId(after: UUID()), root.id)
        XCTAssertEqual(tree.previousPaneId(before: UUID()), second)
    }

    // MARK: - Persistence

    func testTreeSurvivesACodableRoundTrip() {
        let root = leaf("/a")
        let (twoPanes, second) = root.splitting(root.id, direction: .horizontal)
        let (tree, _) = twoPanes.splitting(second, direction: .vertical)

        let data = try! JSONEncoder().encode(tree)
        let decoded = try! JSONDecoder().decode(SplitNode.self, from: data)

        XCTAssertEqual(decoded, tree)
    }
}
