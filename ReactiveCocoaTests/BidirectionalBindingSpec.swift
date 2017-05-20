import Nimble
import Quick
import ReactiveSwift
import ReactiveCocoa
import Result

private final class MockControl {
	var isEnabled = true
	var value: Int?

	let (signal, observer) = Signal<Int, NoError>.pipe()

	func emulateUserInput(_ input: Int) {
		value = input
		observer.send(value: input)
	}
}

class BidirectionalBindingSpec: QuickSpec {
	override func spec() {
		describe("ValueBindable") {
			var valueBindable: ValueBindable<Int>!
			var control: MockControl!

			beforeEach {
				valueBindable = ValueBindable(control: control,
				                              setEnabled: { $0.isEnabled = $1 },
				                              setValue: { $0.value = $1 },
				                              values: { $0.signal })
			}

			afterEach {
				weak var weakControl = control
				control = nil

				expect(weakControl).to(beNil())
			}
		}
	}
}
