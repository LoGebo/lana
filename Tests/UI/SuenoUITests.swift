import XCTest

/// Flujo de Sueño con datos de ejemplo (`-DatosSuenoFake`): no depende de HealthKit ni del reloj.
final class SuenoUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(atPath: "/tmp/lanashots", withIntermediateDirectories: true)
        app.launchArguments += ["-DatosSuenoFake"]
        app.launch()
        app.tabBars.buttons["Protocolos"].tap()
        app.segmentedControls.buttons["Sueño"].tap()
    }

    private func foto(_ n: String) { try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/lanashots/\(n).png")) }

    func testNocheMetricasYPuntajeExplicable() {
        let anoche = app.staticTexts["sueno.anoche"]
        XCTAssertTrue(anoche.waitForExistence(timeout: 15))
        XCTAssertTrue(anoche.label.contains("h"), "duración legible: \(anoche.label)")
        XCTAssertTrue(app.otherElements["sueno.puntaje"].exists || app.staticTexts["sueno.puntaje"].exists || app.descendants(matching: .any)["sueno.puntaje"].exists)
        foto("sueno-1-anoche")

        let explicar = app.buttons["¿Cómo se calcula el puntaje?"]
        for _ in 0..<4 where !explicar.isHittable { app.swipeUp() }
        explicar.tap()
        XCTAssertTrue(app.staticTexts["Duración"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Eficiencia"].exists)
        XCTAssertFalse(app.staticTexts["sueno.vacio"].exists)

        let semana = app.descendants(matching: .any)["sueno.semana"]
        for _ in 0..<6 where !semana.exists { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Promedio 7 días"].exists)
        foto("sueno-2-tendencia")
        for _ in 0..<6 where !app.staticTexts["FC reposo (lpm)"].exists { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["FC reposo (lpm)"].exists)
        foto("sueno-3-cuerpo")
    }

    func testRegistroManualAbreYGuarda() {
        XCTAssertTrue(app.staticTexts["sueno.anoche"].waitForExistence(timeout: 15))
        let boton = app.buttons["sueno.manual"]
        for _ in 0..<10 where !boton.isHittable { app.swipeUp() }
        boton.tap()
        let guardar = app.buttons["sueno.guardar"]
        XCTAssertTrue(guardar.waitForExistence(timeout: 5))
        XCTAssertTrue(guardar.isEnabled, "las fechas por defecto (8 h que terminan hace poco) son válidas")
        foto("sueno-4-manual")
        guardar.tap()
        XCTAssertTrue(app.buttons["sueno.manual"].waitForExistence(timeout: 5))   // la hoja se cerró
    }

    func testHoyMuestraAnoche() {
        app.segmentedControls.buttons["Hoy"].tap()
        XCTAssertTrue(app.staticTexts["Anoche"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Sin datos de sueño"].exists)
    }
}
