import ReactiveSwift
import enum Result.NoError
import UIKit

extension Reactive where Base: UISegmentedControl {
	/// Changes the selected segment of the segmented control.
	public var selectedSegmentIndex: ValueBindable<Int> {
		return makeValueBindable(setValue: { $0.selectedSegmentIndex = $1 }, values: { $0.selectedSegmentIndexes })
	}

	/// A signal of indexes of selections emitted by the segmented control.
	public var selectedSegmentIndexes: Signal<Int, NoError> {
		return controlEvents(.valueChanged).map { $0.selectedSegmentIndex }
	}
}
