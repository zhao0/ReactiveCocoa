import ReactiveSwift
import Result

infix operator <~>: BindingPrecedence

// `ValueBindable` need not conform to `BindingSource`, since the expected public
// APIs for observing user interactions are still the signals named with plural nouns.

public struct ValueBindable<Value>: ActionBindableProtocol, BindingTargetProvider {
	fileprivate weak var control: AnyObject?
	fileprivate let setEnabled: (AnyObject, Bool) -> Void
	fileprivate let setValue: (AnyObject, Value) -> Void
	fileprivate let values: (AnyObject) -> Signal<Value, NoError>
	fileprivate let actionDidBind: ((AnyObject, ActionStates, CompositeDisposable) -> Void)?

	public var bindingTarget: BindingTarget<Value> {
		let lifetime = control.map(lifetime(of:)) ?? .empty
		return BindingTarget(on: UIScheduler(), lifetime: lifetime) { [weak control, setValue] value in
			if let control = control {
				setValue(control, value)
			}
		}
	}

	public var actionBindable: ActionBindable<Value> {
		guard let control = control else { return ActionBindable() }
		return ActionBindable(control: control, setEnabled: setEnabled, values: values, actionDidBind: actionDidBind)
	}

	fileprivate init() {
		control = nil
		setEnabled = { _ in }
		setValue = { _ in }
		values = { _ in .empty }
		actionDidBind = nil
	}

	public init<Control: AnyObject>(
		control: Control,
		setEnabled: @escaping (Control, Bool) -> Void,
		setValue: @escaping (Control, Value) -> Void,
		values: @escaping (Control) -> Signal<Value, NoError>,
		actionDidBind: ((Control, ActionStates, CompositeDisposable) -> Void)? = nil
	) {
		self.control = control
		self.setEnabled = { setEnabled($0 as! Control, $1) }
		self.setValue = { setValue($0 as! Control, $1) }
		self.values = { values($0 as! Control) }
		self.actionDidBind = actionDidBind.map { action in { action($0 as! Control, $1, $2) } }
	}
}

public struct ActionBindable<Value>: ActionBindableProtocol {
	fileprivate weak var control: AnyObject?
	fileprivate let setEnabled: (AnyObject, Bool) -> Void
	fileprivate let values: (AnyObject) -> Signal<Value, NoError>
	fileprivate let actionDidBind: ((AnyObject, ActionStates, CompositeDisposable) -> Void)?

	public var actionBindable: ActionBindable<Value> {
		return self
	}

	fileprivate init() {
		control = nil
		setEnabled = { _ in }
		values = { _ in .empty }
		actionDidBind = nil
	}

	public init<Control: AnyObject>(
		control: Control,
		setEnabled: @escaping (Control, Bool) -> Void,
		values: @escaping (Control) -> Signal<Value, NoError>,
		actionDidBind: ((Control, ActionStates, CompositeDisposable) -> Void)? = nil
	) {
		self.control = control
		self.setEnabled = { setEnabled($0 as! Control, $1) }
		self.values = { values($0 as! Control) }
		self.actionDidBind = actionDidBind.map { action in { action($0 as! Control, $1, $2) } }
	}
}

public protocol ActionBindableProtocol {
	associatedtype Value

	var actionBindable: ActionBindable<Value> { get }
}

public struct ActionStates {
	let isExecuting: SignalProducer<Bool, NoError>

	fileprivate init<Input, Output, Error>(scheduler: UIScheduler, action: Action<Input, Output, Error>) {
		isExecuting = action.isExecuting.producer.observe(on: scheduler)
	}
}

// MARK: Transformation

extension ActionBindableProtocol {
	public func liftOutput<U>(_ transform: @escaping (Signal<Value, NoError>) -> Signal<U, NoError>) -> ActionBindable<U> {
		let bindable = actionBindable
		guard let control = bindable.control else { return ActionBindable() }
		return ActionBindable(control: control,
		                      setEnabled: bindable.setEnabled,
		                      values: { [values = bindable.values] in transform(values($0)) },
		                      actionDidBind: bindable.actionDidBind)
	}

	public func mapOutput<U>(_ transform: @escaping (Value) -> U) -> ActionBindable<U> {
		return liftOutput { $0.map(transform) }
	}

	public func filterOutput(_ transform: @escaping (Value) -> Bool) -> ActionBindable<Value> {
		return liftOutput { $0.filter(transform) }
	}

	public func filterMapOutput<U>(_ transform: @escaping (Value) -> U?) -> ActionBindable<U> {
		return liftOutput { $0.filterMap(transform) }
	}
}

extension ActionBindableProtocol where Value: OptionalProtocol {
	public func skipNilOutput() -> ActionBindable<Value.Wrapped> {
		return liftOutput { $0.skipNil() }
	}
}

// MARK: Binding implementation.

extension ValueBindable {
	fileprivate func bind<P: ComposableMutablePropertyProtocol>(to property: P) -> Disposable? where P.Value == Value {
		return control.flatMap { control in
			return property.withValue { current in
				let disposable = CompositeDisposable()
				let serialDisposable = SerialDisposable()
				let scheduler = UIScheduler()
				var isReplacing = false

				setValue(control, current)

				disposable += property.signal
					.observe { [weak control, setValue] event in
						serialDisposable.inner = scheduler.schedule {
							guard !isReplacing else { return }

							switch event {
							case let .value(value):
								if let control = control {
									setValue(control, value)
								}

							case .completed:
								disposable.dispose()

							case .interrupted, .failed:
								fatalError("Unexpected event.")
							}
						}
				}

				// UI control always takes precedence over changes from the background
				// thread for now.
				//
				// We also take advantage of the fact that `Property` is synchronous to
				// use a boolean flag as a simple & efficient feedback loop breaker.

				disposable += values(control)
					.observeValues { [weak property] value in
						guard let property = property else { return }

						isReplacing = true
						serialDisposable.inner = nil
						property.value = value
						isReplacing = false
				}

				property.lifetime.observeEnded(disposable.dispose)
				ReactiveCocoa.lifetime(of: control).observeEnded(disposable.dispose)

				return ActionDisposable(action: disposable.dispose)
			}
		}
	}
}

extension ActionBindableProtocol {
	fileprivate func bind<Output, Error>(to action: Action<Value, Output, Error>) -> Disposable? {
		let bindable = actionBindable
		return bindable.control.flatMap { control in
			let disposable = CompositeDisposable()
			let scheduler = UIScheduler()

			disposable += bindable.values(control).observeValues { [weak action] value in
				action?.apply(value).start()
			}

			disposable += action.isEnabled.producer
				.observe(on: scheduler)
				.startWithValues { [weak control, setEnabled = bindable.setEnabled] isEnabled in
					guard let control = control else { return }
					setEnabled(control, isEnabled)
			}


			action.lifetime.observeEnded(disposable.dispose)
			ReactiveCocoa.lifetime(of: control).observeEnded(disposable.dispose)

			bindable.actionDidBind?(control, ActionStates(scheduler: scheduler, action: action), disposable)

			return ActionDisposable(action: disposable.dispose)
		}
	}
}

// MARK: Value bindings

extension ComposableMutablePropertyProtocol {
	/// Create a value binding between `bindable` and `property`.
	///
	/// The binding would use the current value of `property` as the initial value. It
	/// would prefer changes initiated on the main queue by `bindable`.
	///
	/// ## Example
	/// ```
	/// // Both are equivalent.
	/// heaterSwitch.reactive.isOn <~> viewModel.isHeaterTurnedOn
	/// viewModel.isHeaterTurnedOn <~> heaterSwitch.reactive.isOn
	/// ```
	///
	/// - parameters:
	///   - property: The property to bind with.
	///   - bindable: The value bindable to bind with.
	///
	/// - returns: A `Disposable` that can be used to tear down the value binding.
	@discardableResult
	public static func <~>(property: Self, bindable: ValueBindable<Value>) -> Disposable? {
		return bindable <~> property
	}
}

extension ValueBindable {
	/// Create a value binding between `bindable` and `property`.
	/// 
	/// The binding would use the current value of `property` as the initial value. It 
	/// would prefer changes initiated on the main queue by `bindable`.
	///
	/// ## Example
	/// ```
	/// // Both are equivalent.
	/// heaterSwitch.reactive.isOn <~> viewModel.isHeaterTurnedOn
	/// viewModel.isHeaterTurnedOn <~> heaterSwitch.reactive.isOn
	/// ```
	///
	/// - parameters:
	///   - bindable: The value bindable to bind with.
	///   - property: The property to bind with.
	///
	/// - returns: A `Disposable` that can be used to tear down the value binding.
	@discardableResult
	public static func <~> <P: ComposableMutablePropertyProtocol>(bindable: ValueBindable, property: P) -> Disposable? where P.Value == Value {
		return bindable.bind(to: property)
	}
}


// MARK: Action bindings

extension Action {
	/// Create an action binding between `bindable` and `action`.
	///
	/// The availability of the `bindable` is bound to the availability of `action`, and
	/// any value initiated by the `bindable` would be turned into an execution attempt of
	/// `action`. Errors of the `Action` are ignored by the binding.
	///
	/// ## Example
	/// ```
	/// // Both are equivalent.
	/// confirmButton.reactive.pressed <~> viewModel.submit
	/// viewModel.submit <~> confirmButton.reactive.pressed
	/// ```
	///
	/// - parameters:
	///   - bindable: The value bindable to bind with.
	///   - action: The `Action` to bind with.
	///
	/// - returns: A `Disposable` that can be used to tear down the action binding.
	@discardableResult
	public static func <~><Bindable>(action: Action, bindable: Bindable) -> Disposable? where Bindable: ActionBindableProtocol, Bindable.Value == Input {
		return bindable <~> action
	}
}

extension Action where Input == () {
	/// Create an action binding between `bindable` and `action`.
	///
	/// The availability of the `bindable` is bound to the availability of `action`, and
	/// any value initiated by the `bindable` would be turned into an execution attempt of
	/// `action`. Errors of the `Action` are ignored by the binding.
	///
	/// ## Example
	/// ```
	/// // Both are equivalent.
	/// confirmButton.reactive.pressed <~> viewModel.submit
	/// viewModel.submit <~> confirmButton.reactive.pressed
	/// ```
	///
	/// - parameters:
	///   - bindable: The value bindable to bind with.
	///   - action: The `Action` to bind with.
	///
	/// - returns: A `Disposable` that can be used to tear down the action binding.
	@discardableResult
	public static func <~> <Bindable>(action: Action, bindable: Bindable) -> Disposable? where Bindable: ActionBindableProtocol {
		return bindable <~> action
	}

	/// Create an action binding between `bindable` and `action`.
	///
	/// The availability of the `bindable` is bound to the availability of `action`, and
	/// any value initiated by the `bindable` would be turned into an execution attempt of
	/// `action`. Errors of the `Action` are ignored by the binding.
	///
	/// ## Example
	/// ```
	/// // Both are equivalent.
	/// confirmButton.reactive.pressed <~> viewModel.submit
	/// viewModel.submit <~> confirmButton.reactive.pressed
	/// ```
	///
	/// - parameters:
	///   - bindable: The value bindable to bind with.
	///   - action: The `Action` to bind with.
	///
	/// - returns: A `Disposable` that can be used to tear down the action binding.
	@discardableResult
	public static func <~> <Bindable>(action: Action, bindable: Bindable) -> Disposable? where Bindable: ActionBindableProtocol, Bindable.Value == () {
		return bindable <~> action
	}
}

extension ActionBindableProtocol {
	/// Create an action binding between `bindable` and `action`.
	///
	/// The availability of the `bindable` is bound to the availability of `action`, and
	/// any value initiated by the `bindable` would be turned into an execution attempt of
	/// `action`. Errors of the `Action` are ignored by the binding.
	///
	/// ## Example
	/// ```
	/// // Both are equivalent.
	/// confirmButton.reactive.pressed <~> viewModel.submit
	/// viewModel.submit <~> confirmButton.reactive.pressed
	/// ```
	///
	/// - parameters:
	///   - bindable: The value bindable to bind with.
	///   - action: The `Action` to bind with.
	///
	/// - returns: A `Disposable` that can be used to tear down the action binding.
	@discardableResult
	public static func <~> <Output, Error>(bindable: Self, action: Action<Value, Output, Error>) -> Disposable? {
		return bindable.bind(to: action)
	}

	/// Create an action binding between `bindable` and `action`.
	///
	/// The availability of the `bindable` is bound to the availability of `action`, and
	/// any value initiated by the `bindable` would be turned into an execution attempt of
	/// `action`. Errors of the `Action` are ignored by the binding.
	///
	/// ## Example
	/// ```
	/// // Both are equivalent.
	/// confirmButton.reactive.pressed <~> viewModel.submit
	/// viewModel.submit <~> confirmButton.reactive.pressed
	/// ```
	///
	/// - parameters:
	///   - bindable: The value bindable to bind with.
	///   - action: The `Action` to bind with.
	///
	/// - returns: A `Disposable` that can be used to tear down the action binding.
	@discardableResult
	public static func <~> <Output, Error>(bindable: Self, action: Action<(), Output, Error>) -> Disposable? {
		return bindable.mapOutput { _ in } <~> action
	}
}

extension ActionBindableProtocol where Value == () {
	/// Create an action binding between `bindable` and `action`.
	///
	/// The availability of the `bindable` is bound to the availability of `action`, and
	/// any value initiated by the `bindable` would be turned into an execution attempt of
	/// `action`. Errors of the `Action` are ignored by the binding.
	///
	/// ## Example
	/// ```
	/// // Both are equivalent.
	/// confirmButton.reactive.pressed <~> viewModel.submit
	/// viewModel.submit <~> confirmButton.reactive.pressed
	/// ```
	///
	/// - parameters:
	///   - bindable: The value bindable to bind with.
	///   - action: The `Action` to bind with.
	///
	/// - returns: A `Disposable` that can be used to tear down the action binding.
	@discardableResult
	public static func <~> <Output, Error>(bindable: Self, action: Action<(), Output, Error>) -> Disposable? {
		return bindable.bind(to: action)
	}
}
