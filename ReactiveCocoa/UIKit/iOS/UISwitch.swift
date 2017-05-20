import ReactiveSwift
import enum Result.NoError
import UIKit

extension Reactive where Base: UISwitch {
	/// Sets the on-off state of the switch.
	public var isOn: ValueBindable<Bool> {
		return makeValueBindable(setValue: { $0.isOn = $1 }, values: { $0.isOnValues })
	}

	/// A signal of on-off states in `Bool` emitted by the switch.
	public var isOnValues: Signal<Bool, NoError> {
		return controlEvents(.valueChanged).map { $0.isOn }
	}
}
