import ReactiveSwift
import UIKit
import enum Result.NoError

extension Reactive where Base: UITextView {
	internal func makeValueBindable<U>(setValue: @escaping (Base, U) -> Void, values: @escaping (Reactive<Base>) -> Signal<U, NoError>) -> ValueBindable<U> {
		return ValueBindable(control: base,
		                       setEnabled: { $0.isEditable = $1 },
		                       setValue: setValue,
		                       values: { values(($0 as! Base).reactive) })
	}

	/// Sets the text of the text view.
	public var text: ValueBindable<String?> {
		return makeValueBindable(setValue: { $0.text = $1 }, values: { $0.textValues })
	}

	/// Sets the text of the text view.
	public var continuousText: ValueBindable<String?> {
		return makeValueBindable(setValue: { $0.text = $1 }, values: { $0.continuousTextValues })
	}

	private func textValues(forName name: NSNotification.Name) -> Signal<String?, NoError> {
		return NotificationCenter.default
			.reactive
			.notifications(forName: name, object: base)
			.take(during: lifetime)
			.map { ($0.object as! UITextView).text! }
	}

	/// A signal of text values emitted by the text view upon end of editing.
	///
	/// - note: To observe text values that change on all editing events,
	///   see `continuousTextValues`.
	public var textValues: Signal<String?, NoError> {
		return textValues(forName: .UITextViewTextDidEndEditing)
	}

	/// A signal of text values emitted by the text view upon any changes.
	///
	/// - note: To observe text values only when editing ends, see `textValues`.
	public var continuousTextValues: Signal<String?, NoError> {
		return textValues(forName: .UITextViewTextDidChange)
	}

	/// Sets the attributed text of the text view.
	public var attributedText: ValueBindable<NSAttributedString?> {
		return makeValueBindable(setValue: { $0.attributedText = $1 }, values: { $0.attributedTextValues })
	}

	/// Sets the attributed text of the text view.
	public var continuousAttributedText: ValueBindable<NSAttributedString?> {
		return makeValueBindable(setValue: { $0.attributedText = $1 }, values: { $0.continuousAttributedTextValues })
	}
	
	private func attributedTextValues(forName name: NSNotification.Name) -> Signal<NSAttributedString?, NoError> {
		return NotificationCenter.default
			.reactive
			.notifications(forName: name, object: base)
			.take(during: lifetime)
			.map { ($0.object as! UITextView).attributedText! }
	}
	
	/// A signal of attributed text values emitted by the text view upon end of editing.
	///
	/// - note: To observe attributed text values that change on all editing events,
	///   see `continuousAttributedTextValues`.
	public var attributedTextValues: Signal<NSAttributedString?, NoError> {
		return attributedTextValues(forName: .UITextViewTextDidEndEditing)
	}
	
	/// A signal of attributed text values emitted by the text view upon any changes.
	///
	/// - note: To observe text values only when editing ends, see `attributedTextValues`.
	public var continuousAttributedTextValues: Signal<NSAttributedString?, NoError> {
		return attributedTextValues(forName: .UITextViewTextDidChange)
	}
}
