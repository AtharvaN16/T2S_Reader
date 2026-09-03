import Testing
import T2SCore
@testable import T2SApp

@Suite struct SpeedPickerModelTests {
    @Test func rowsCoverEveryRateAndMarkAvailability() {
        #expect(SpeedPickerModel.rates.count == 36 && SpeedPickerModel.rates.first == 0.5 && SpeedPickerModel.rates.last == 4.0)
        let model = SpeedPickerModel.make(current: 1.5, maxRate: 2.0)
        #expect(model.rows.count == 36)
        #expect(model.rows.first?.label == "0.5x" && model.rows.last?.label == "4x")
        #expect(model.rows.first { abs($0.rate - 1.5) < 0.001 }?.isCurrent == true)
        #expect(model.rows.filter(\.isCurrent).count == 1)
        #expect(model.rows.first { abs($0.rate - 2.0) < 0.001 }?.isAvailable == true)
        #expect(model.rows.first { abs($0.rate - 2.1) < 0.001 }?.isAvailable == false)
        #expect(model.footnote == "Rates above 2x can't be sustained on this device right now.")
        #expect(SpeedPickerModel.make(current: 1.0, maxRate: 4.0).footnote == nil)
        #expect(SpeedPickerModel.label(for: 1.0) == "1x" && SpeedPickerModel.label(for: 1.25) == "1.3x" && SpeedPickerModel.label(for: 0.5) == "0.5x")
    }
}
