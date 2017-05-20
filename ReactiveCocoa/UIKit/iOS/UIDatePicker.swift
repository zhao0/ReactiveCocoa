import ReactiveSwift
import enum Result.NoError
import UIKit

extension Reactive where Base: UIDatePicker {
	/// Sets the date of the date picker.
	public var date: ValueBindable<Date> {
		return makeValueBindable(setValue: { $0.date = $1 }, values: { $0.dates })
	}

	/// A signal of dates emitted by the date picker.
	public var dates: Signal<Date, NoError> {
		return controlEvents(.valueChanged).map { $0.date }
	}
}
