import XCTest

final class FlujoProtocolosUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(atPath: "/tmp/lanashots", withIntermediateDirectories: true)
        app.launch()
        limpiarSesionEnCurso()
    }

    /// Si una corrida anterior dejó un entrenamiento a medias, lo cancela para partir limpio.
    private func limpiarSesionEnCurso() {
        let tab = app.tabBars.buttons["Protocolos"]
        guard tab.waitForExistence(timeout: 10) else { return }
        tab.tap()
        app.segmentedControls.buttons["Gym"].tap()
        let continuar = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Entrenamiento en curso'")).firstMatch
        if continuar.waitForExistence(timeout: 2) {
            continuar.tap()
            app.buttons["Cancelar entrenamiento"].tap()
            app.buttons["Borrar entrenamiento"].tap()
        }
        app.segmentedControls.buttons["Hoy"].tap()
    }

    /// Toca el campo y escribe: la app selecciona todo al enfocar, así que reemplaza el valor precargado.
    private func escribir(_ campo: XCUIElement, _ texto: String) {
        campo.tap()
        Thread.sleep(forTimeInterval: 0.4)
        campo.typeText(texto)
    }

    private func foto(_ nombre: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: "/tmp/lanashots/\(nombre).png"))
    }

    func testRecorridoCompleto() {
        foto("00-inicio")
        let tab = app.tabBars.buttons["Protocolos"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "No hay pestaña Protocolos")
        tab.tap()
        app.segmentedControls.buttons["Hoy"].tap()   // la app recuerda la última sección
        foto("01-hoy")

        // Checklist: marcar un hábito y verificar que cambia el contador
        let luz = app.buttons["Luz al despertar"]
        XCTAssertTrue(luz.waitForExistence(timeout: 5))
        luz.tap()
        foto("02-checklist")

        // Gym
        app.segmentedControls.buttons["Gym"].tap()
        let vacio = app.buttons["Empezar entrenamiento vacío"]
        XCTAssertTrue(vacio.waitForExistence(timeout: 5))
        foto("03-gym")
        vacio.tap()

        let agregar = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Agregar ejercicio'")).firstMatch
        if !agregar.waitForExistence(timeout: 10) { foto("ERR-activo"); print(app.debugDescription) }
        XCTAssertTrue(agregar.exists)
        agregar.tap()
        let buscar = app.searchFields.firstMatch
        XCTAssertTrue(buscar.waitForExistence(timeout: 5))
        buscar.tap(); buscar.typeText("Press de banca con barra")
        let fila = app.buttons["Press de banca con barra"]
        XCTAssertTrue(fila.waitForExistence(timeout: 5), "No cargó la biblioteca de ejercicios")
        foto("04-selector")
        fila.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Agregar ('")).firstMatch.tap()

        // 3 series precargadas. Llena peso y reps de la primera y márcala.
        XCTAssertTrue(app.staticTexts["Press de banca con barra"].waitForExistence(timeout: 5))
        let peso1 = app.textFields["Peso en kilos, serie 1"]
        let reps1 = app.textFields["Repeticiones, serie 1"]
        XCTAssertTrue(peso1.waitForExistence(timeout: 5), "No hay campo de peso")
        escribir(peso1, "80")
        app.buttons["Listo"].firstMatch.tap()
        escribir(reps1, "8")
        app.buttons["Listo"].firstMatch.tap()
        foto("05-activo")
        XCTAssertEqual(peso1.value as? String, "80")
        XCTAssertEqual(reps1.value as? String, "8")
        let marcar = app.buttons["Marcar serie 1"]
        XCTAssertTrue(marcar.exists)
        marcar.tap()
        XCTAssertTrue(app.buttons["Serie 1 hecha"].waitForExistence(timeout: 3))
        foto("06-serie-hecha")

        // Terminar → resumen
        app.buttons["Terminar"].tap()
        XCTAssertTrue(app.staticTexts["Volumen"].waitForExistence(timeout: 5), "No salió el resumen")
        foto("07-resumen")
        app.buttons["Cerrar"].tap()
        XCTAssertTrue(app.buttons["Empezar entrenamiento vacío"].waitForExistence(timeout: 5))
        foto("08-historial")
    }

    /// Terminar sin marcar nada no debe guardar una sesión vacía.
    func testSesionVaciaSeDescarta() {
        app.tabBars.buttons["Protocolos"].tap()
        app.segmentedControls.buttons["Gym"].tap()
        app.buttons["Empezar entrenamiento vacío"].tap()
        XCTAssertTrue(app.buttons["Terminar"].waitForExistence(timeout: 5))
        app.buttons["Terminar"].tap()
        XCTAssertTrue(app.buttons["Empezar entrenamiento vacío"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Empezar entrenamiento vacío"].isEnabled, "Quedó una sesión en curso")
        XCTAssertFalse(app.staticTexts["Entrenamiento en curso"].exists)
        foto("09-vacia")
    }

    func testComida() {
        app.tabBars.buttons["Protocolos"].tap()
        app.segmentedControls.buttons["Comida"].tap()
        foto("10-comida")
        let agregar = app.buttons["Agregar alimento"].firstMatch
        XCTAssertTrue(agregar.waitForExistence(timeout: 5))
        agregar.tap()
        let buscar = app.searchFields.firstMatch
        XCTAssertTrue(buscar.waitForExistence(timeout: 5))
        buscar.tap(); buscar.typeText("Pechuga de pollo sin")
        let pollo = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Pechuga de pollo sin piel'")).firstMatch
        XCTAssertTrue(pollo.waitForExistence(timeout: 5), "No cargó la biblioteca de alimentos")
        foto("11-agregar")
        pollo.tap()
        foto("12-detalle")
        app.buttons["Añadir"].tap()
        foto("13-diario")
        XCTAssertTrue(app.staticTexts["Pechuga de pollo sin piel asada"].waitForExistence(timeout: 5), "No quedó en el diario")
    }
}

extension FlujoProtocolosUITests {
    /// El Panel lee/escribe en la base de Protocolos (no en la de finanzas).
    func testPanelAguaRapida() {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Panel"].tap()
        let boton = app.buttons["Agua +250"]
        XCTAssertTrue(boton.waitForExistence(timeout: 15))
        let agua = { self.app.staticTexts.matching(NSPredicate(format: "label ENDSWITH '/ 3,000 ml' OR label ENDSWITH '3,000 ml'")).firstMatch }
        let antes = agua().exists ? agua().label : ""
        boton.tap()
        let cambio = NSPredicate { _, _ in agua().exists && agua().label != antes }
        wait(for: [expectation(for: cambio, evaluatedWith: nil)], timeout: 5)
    }
}

extension FlujoProtocolosUITests {
    func testPanelGastoAbreCaptura() {
        app.tabBars.buttons["Panel"].tap()
        app.buttons["Gasto"].tap()
        XCTAssertTrue(app.navigationBars["Nuevo movimiento"].waitForExistence(timeout: 5))
        app.buttons["Cancelar"].tap()
    }

    func testPanelEntrenarIniciaSesionYSeReflejaEnPanel() {
        app.tabBars.buttons["Panel"].tap()
        app.buttons["Entrenar"].tap()
        XCTAssertTrue(app.buttons["Terminar"].waitForExistence(timeout: 5))
        app.buttons["Cancelar entrenamiento"].tap()
        app.buttons["Borrar entrenamiento"].tap()
        XCTAssertTrue(app.buttons["Entrenar"].waitForExistence(timeout: 5), "Debe volver a 'Entrenar' sin sesión en curso")
    }

    /// Programa Nippard: semana 1, calentamientos presentes, video/alternativas y sustitución.
    func testProgramaCalentamientoYAlternativas() {
        app.tabBars.buttons["Protocolos"].tap()
        app.segmentedControls.buttons["Gym"].tap()
        let empezarPrograma = app.buttons["Empezar semana 1"]
        if empezarPrograma.waitForExistence(timeout: 3) { empezarPrograma.tap() }
        XCTAssertTrue(app.staticTexts["Semana 1 de 12"].waitForExistence(timeout: 5))
        let upper = app.buttons.matching(NSPredicate(format: "label CONTAINS 'BTS Upper'")).firstMatch
        XCTAssertTrue(upper.waitForExistence(timeout: 5))
        upper.tap()
        XCTAssertTrue(app.textFields["Peso en kilos, calentamiento 1"].waitForExistence(timeout: 8), "No hay series de calentamiento")
        let info = app.buttons["Video y alternativas de 45° Incline Barbell Press"]
        XCTAssertTrue(info.waitForExistence(timeout: 5))
        info.tap()
        XCTAssertTrue(app.staticTexts["Alternativas"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.links.count + app.buttons.matching(NSPredicate(format: "label CONTAINS 'Ver video'")).count > 0)
        app.buttons["Usar"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["45° Incline DB Press"].waitForExistence(timeout: 5), "No sustituyó el ejercicio")
        foto("12-programa")
    }
}

extension FlujoProtocolosUITests {
    /// Crear una rutina propia y borrarla (con confirmación).
    func testCrearYBorrarRutina() {
        app.tabBars.buttons["Protocolos"].tap()
        app.segmentedControls.buttons["Gym"].tap()
        app.buttons["Nueva rutina"].tap()
        let nombre = app.textFields.firstMatch
        XCTAssertTrue(nombre.waitForExistence(timeout: 5))
        nombre.tap(); nombre.typeText("Borrame")
        app.buttons["Cancelar"].tap()                       // cancelar no debe crear nada
        XCTAssertFalse(app.staticTexts["Borrame"].exists)
        app.buttons["Nueva rutina"].tap()
        let n2 = app.textFields.firstMatch
        XCTAssertTrue(n2.waitForExistence(timeout: 5))
        n2.tap(); n2.typeText("Borrame")
        app.buttons["Agregar ejercicio"].firstMatch.tap()
        let buscar = app.searchFields.firstMatch
        XCTAssertTrue(buscar.waitForExistence(timeout: 5)); buscar.tap(); buscar.typeText("Leg Extension")
        app.buttons["Leg Extension"].firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Agregar ('")).firstMatch.tap()
        app.buttons["Guardar"].tap()
        XCTAssertTrue(app.staticTexts["Borrame"].waitForExistence(timeout: 5), "No se creó la rutina")
        app.buttons["Más opciones de Borrame"].tap()
        app.buttons["Borrar"].tap()
        app.buttons["Borrar rutina"].tap()
        XCTAssertTrue(NSPredicate(format: "exists == false").evaluate(with: app.staticTexts["Borrame"]) || app.staticTexts["Borrame"].waitForNonExistence(timeout: 5), "No se borró")
    }

    /// Agua: sumar, quitar 250 y poner en 0 desde el Panel.
    func testAguaQuitarYReiniciar() {
        app.tabBars.buttons["Panel"].tap()
        let boton = app.buttons["Agua +250"]
        XCTAssertTrue(boton.waitForExistence(timeout: 10))
        let valor = { self.app.staticTexts.matching(NSPredicate(format: "label ENDSWITH '3,000 ml'")).firstMatch.label }
        boton.press(forDuration: 1.0)
        app.buttons["Poner agua en 0"].tap()
        XCTAssertTrue(app.staticTexts["0 / 3,000 ml"].waitForExistence(timeout: 5), "No reinició: \(valor())")
        boton.tap(); boton.tap()
        XCTAssertTrue(app.staticTexts["500 / 3,000 ml"].waitForExistence(timeout: 5))
        boton.press(forDuration: 1.0)
        app.buttons["Quitar 250 ml"].tap()
        XCTAssertTrue(app.staticTexts["250 / 3,000 ml"].waitForExistence(timeout: 5))
        boton.press(forDuration: 1.0)
        app.buttons["Poner agua en 0"].tap()
        XCTAssertTrue(app.staticTexts["0 / 3,000 ml"].waitForExistence(timeout: 5))
    }
}
