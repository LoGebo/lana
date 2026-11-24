import XCTest
@testable import Lana

final class PesoTests: XCTestCase {
    private func serie(_ kgs: [Double]) -> [(dia: Date, kg: Double)] {
        let hoy = Calendar.current.startOfDay(for: Date())
        return kgs.enumerated().map { (Calendar.current.date(byAdding: .day, value: $0.offset - kgs.count + 1, to: hoy)!, $0.element) }
    }
    func testTendencia() {
        let t = Peso.tendenciaSemanal(serie([75, 75.1, 75.2, 75.3, 75.4, 75.5, 75.6, 75.7]))!
        XCTAssertEqual(t, 0.7, accuracy: 0.01)
    }
    func testPocosDatos() {
        XCTAssertNil(Peso.tendenciaSemanal(serie([75, 75.2])))
        XCTAssertNil(Peso.tendenciaSemanal(serie([75, 75.2, 75.1])))   // <5 días de rango
    }
    func testSugerencia() {
        XCTAssertEqual(Peso.sugerencia(kgPorSemana: 0.0, pesoActual: 75).kcal, 200)
        XCTAssertEqual(Peso.sugerencia(kgPorSemana: 0.25, pesoActual: 75).kcal, 0)
        XCTAssertEqual(Peso.sugerencia(kgPorSemana: 0.6, pesoActual: 75).kcal, -200)
    }
    func testRangoValido() {
        XCTAssertFalse(Peso.rango.contains(.nan)); XCTAssertFalse(Peso.rango.contains(-5)); XCTAssertTrue(Peso.rango.contains(75))
    }
}
