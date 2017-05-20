import ReactiveSwift
import enum Result.NoError
import UIKit

extension Reactive where Base: UIRefreshControl {
	/// Sets whether the refresh control should be refreshing.
	public var isRefreshing: ValueBindable<Bool> {
		return makeValueBindable(setValue: { $1 ? $0.beginRefreshing() : $0.endRefreshing() },
		                         values: { $0.controlEvents(.valueChanged).map { $0.isRefreshing } },
		                         actionDidBind: { $2 += $0.reactive.isRefreshing <~ $1.isExecuting })
	}

	/// Sets the attributed title of the refresh control.
	public var attributedTitle: BindingTarget<NSAttributedString?> {
		return makeBindingTarget { $0.attributedTitle = $1 }
	}
}
