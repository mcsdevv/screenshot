import XCTest
@testable import ScreenCapture

final class StorageLocationSelectionCoordinatorTests: XCTestCase {
    func testActionForChangeIgnoresSuppressedHydrationUpdate() {
        let action = StorageLocationSelectionCoordinator.actionForChange(
            oldValue: "default",
            newValue: "custom",
            suppressNextChange: true
        )

        XCTAssertEqual(action, .ignore)
    }

    func testActionForChangeUsesCustomPickerForCustomSelection() {
        let action = StorageLocationSelectionCoordinator.actionForChange(
            oldValue: "desktop",
            newValue: "custom",
            suppressNextChange: false
        )

        XCTAssertEqual(action, .chooseCustomFolder(revertTo: "desktop"))
    }

    func testActionForChangePersistsNonCustomSelection() {
        let action = StorageLocationSelectionCoordinator.actionForChange(
            oldValue: "custom",
            newValue: "default",
            suppressNextChange: false
        )

        XCTAssertEqual(action, .setStorageLocation("default"))
    }

    func testSelectionAfterPickerCancelRevertsToPreviousSelection() {
        let selection = StorageLocationSelectionCoordinator.selectionAfterCustomFolderPicker(
            isConfirmed: false,
            didPersistCustomFolder: false,
            currentSelection: "custom",
            revertSelection: "desktop"
        )

        XCTAssertEqual(selection, "desktop")
    }

    func testSelectionAfterPickerFailureRevertsToPreviousSelection() {
        let selection = StorageLocationSelectionCoordinator.selectionAfterCustomFolderPicker(
            isConfirmed: true,
            didPersistCustomFolder: false,
            currentSelection: "custom",
            revertSelection: "default"
        )

        XCTAssertEqual(selection, "default")
    }

    func testSelectionAfterPickerCancelKeepsCurrentWhenNoRevertSelectionProvided() {
        let selection = StorageLocationSelectionCoordinator.selectionAfterCustomFolderPicker(
            isConfirmed: false,
            didPersistCustomFolder: false,
            currentSelection: "custom",
            revertSelection: nil
        )

        XCTAssertEqual(selection, "custom")
    }

    func testSelectionAfterPickerSuccessStaysCustom() {
        let selection = StorageLocationSelectionCoordinator.selectionAfterCustomFolderPicker(
            isConfirmed: true,
            didPersistCustomFolder: true,
            currentSelection: "custom",
            revertSelection: "default"
        )

        XCTAssertEqual(selection, "custom")
    }
}
