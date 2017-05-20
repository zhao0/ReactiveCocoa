import ReactiveSwift
import UIKit
import enum Result.NoError

extension Reactive where Base: UIControl {
	internal func makeActionBindable(for controlEvent: UIControlEvents) -> ActionBindable<Base> {
		return ActionBindable(control: base,
		                      setEnabled: { $0.isEnabled = $1 },
		                      values: { $0.reactive.controlEvents(controlEvent) })
	}

	internal func makeValueBindable<U>(setValue: @escaping (Base, U) -> Void, values: @escaping (Reactive<Base>) -> Signal<U, NoError>, actionDidBind: ((Base, ActionStates, CompositeDisposable) -> Void)? = nil) -> ValueBindable<U> {
		return ValueBindable(control: base,
		                     setEnabled: { $0.isEnabled = $1 },
		                     setValue: setValue,
		                     values: { values($0.reactive) },
		                     actionDidBind: actionDidBind)
	}

	/// Create a signal which sends a `value` event for each of the specified
	/// control events.
	///
	/// - parameters:
	///   - controlEvents: The control event mask.
	///
	/// - returns: A signal that sends the control each time the control event 
	///            occurs.
	public func controlEvents(_ controlEvents: UIControlEvents) -> Signal<Base, NoError> {
		return Signal { observer in
			let receiver = CocoaTarget(observer) { $0 as! Base }
			base.addTarget(receiver,
			               action: #selector(receiver.sendNext),
			               for: controlEvents)

			let disposable = lifetime.ended.observeCompleted(observer.sendCompleted)

			return ActionDisposable { [weak base = self.base] in
				disposable?.dispose()

				base?.removeTarget(receiver,
				                   action: #selector(receiver.sendNext),
				                   for: controlEvents)
			}
		}
	}

	@available(*, unavailable, renamed: "controlEvents(_:)")
	public func trigger(for controlEvents: UIControlEvents) -> Signal<(), NoError> {
		fatalError()
	}

	/// Sets whether the control is enabled.
	public var isEnabled: BindingTarget<Bool> {
		return makeBindingTarget { $0.isEnabled = $1 }
	}

	/// Sets whether the control is selected.
	public var isSelected: BindingTarget<Bool> {
		return makeBindingTarget { $0.isSelected = $1 }
	}

	/// Sets whether the control is highlighted.
	public var isHighlighted: BindingTarget<Bool> {
		return makeBindingTarget { $0.isHighlighted = $1 }
	}
}
