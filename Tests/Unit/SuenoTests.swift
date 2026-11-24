import XCTest
import SwiftData
@testable import Lana

@MainActor
final class SuenoTests: XCTestCase {
    private func calendario(_ tz: String = "America/Mexico_City") -> Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: tz)!; return c
    }
    private lazy var cal = calendario()
    private func f(_ cal: Calendar, _ m: Int, _ d: Int, _ h: Int, _ mi: Int = 0, y: Int = 2026) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))!
    }
    private func m(_ a: Date, _ min: Double, _ e: EtapaSueno, _ fuente: String = "watch") -> MuestraSueno {
        MuestraSueno(inicio: a, fin: a.addingTimeInterval(min * 60), etapa: e, fuente: fuente)
    }
    private let ahora = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Unificar

    func testWatchEIphoneNoDuplicanTiempo() {
        let t = ahora.addingTimeInterval(-86400)
        let segs = AnalisisSueno.unificar([m(t, 240, .nucleo), m(t, 420, .sinEtapa, "iphone")], ahora: ahora)
        XCTAssertEqual(segs.reduce(0) { $0 + $1.minutos }, 420, accuracy: 0.01)          // 7 h, no 11
        XCTAssertEqual(segs[0].etapa, .nucleo)                                           // el Watch manda donde hay etapas
        for (a, b) in zip(segs, segs.dropFirst()) { XCTAssertLessThanOrEqual(a.fin, b.inicio) }
    }

    func testDespiertoDelWatchGanaAlIphone() {
        let t = ahora.addingTimeInterval(-86400)
        let segs = AnalisisSueno.unificar([m(t, 480, .sinEtapa, "iphone"), m(t, 180, .nucleo), m(t.addingTimeInterval(180 * 60), 30, .despierto),
                                           m(t.addingTimeInterval(210 * 60), 270, .nucleo)], ahora: ahora)
        let n = AnalisisSueno.sesiones(segs, cal: cal)[0]
        XCTAssertEqual(n.minDormido, 450, accuracy: 0.01)
        XCTAssertEqual(n.minDespierto, 30, accuracy: 0.01)
    }

    func testEnCamaSolaNoEsSueno() {
        let segs = AnalisisSueno.unificar([m(ahora.addingTimeInterval(-36000), 480, .enCama, "iphone")], ahora: ahora)
        XCTAssertTrue(AnalisisSueno.sesiones(segs, cal: cal).isEmpty)
    }

    func testMuestrasCorruptasSeIgnoran() {
        let t = ahora.addingTimeInterval(-86400)
        let malas = [MuestraSueno(inicio: t, fin: t, etapa: .nucleo, fuente: "x"),                                   // dura 0
                     MuestraSueno(inicio: t.addingTimeInterval(60), fin: t, etapa: .nucleo, fuente: "x"),             // fin antes que inicio
                     m(t, 25 * 60, .nucleo),                                                                         // > 24 h
                     m(ahora.addingTimeInterval(7200), 60, .nucleo),                                                  // empieza en el futuro
                     MuestraSueno(inicio: t, fin: Date(timeIntervalSince1970: .infinity), etapa: .nucleo, fuente: "x")]
        XCTAssertTrue(AnalisisSueno.unificar(malas, ahora: ahora).isEmpty)
        XCTAssertTrue(AnalisisSueno.unificar([], ahora: ahora).isEmpty)
        XCTAssertEqual(AnalisisSueno.unificar(malas + [m(t, 60, .nucleo)], ahora: ahora).count, 1)   // las buenas sobreviven
    }

    // MARK: Noches, siestas, medianoche, DST

    func testNocheQueCruzaMedianocheVaAlDiaDeDespertar() {
        let n = AnalisisSueno.sesiones(AnalisisSueno.unificar([m(f(cal, 3, 10, 23), 480, .nucleo)], ahora: f(cal, 3, 12, 0)), cal: cal)
        XCTAssertEqual(n.count, 1)
        XCTAssertEqual(n[0].dia, cal.startOfDay(for: f(cal, 3, 11, 12)))
        XCTAssertFalse(n[0].siesta)
    }

    func testSiestaSeparadaDeLaNoche() {
        let segs = AnalisisSueno.unificar([m(f(cal, 3, 10, 23), 450, .nucleo), m(f(cal, 3, 11, 14), 40, .nucleo)], ahora: f(cal, 3, 12, 0))
        let r = AnalisisSueno.sesiones(segs, cal: cal)
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r.filter(\.siesta).count, 1)
        XCTAssertEqual(r.first { $0.siesta }?.minDormido ?? 0, 40, accuracy: 0.01)
        XCTAssertEqual(r.first { !$0.siesta }?.minDormido ?? 0, 450, accuracy: 0.01)
    }

    func testDosBloquesLargosElMismoDiaSoloUnaEsNoche() {
        let segs = AnalisisSueno.unificar([m(f(cal, 3, 11, 1), 240, .nucleo), m(f(cal, 3, 11, 13), 360, .nucleo)], ahora: f(cal, 3, 12, 0))
        let r = AnalisisSueno.sesiones(segs, cal: cal)
        XCTAssertEqual(r.filter { !$0.siesta }.count, 1)
        XCTAssertEqual(r.first { !$0.siesta }?.minDormido ?? 0, 360, accuracy: 0.01)
    }

    func testDespertarEnLaMadrugadaNoParteLaNocheYBajaEficiencia() {
        let t = f(cal, 3, 10, 23)
        let segs = AnalisisSueno.unificar([m(t, 180, .nucleo), m(t.addingTimeInterval(180 * 60), 60, .despierto),
                                           m(t.addingTimeInterval(240 * 60), 240, .nucleo)], ahora: f(cal, 3, 12, 0))
        let r = AnalisisSueno.sesiones(segs, cal: cal)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].minDormido, 420, accuracy: 0.01)
        XCTAssertEqual(r[0].eficiencia, 420.0 / 480.0, accuracy: 0.001)
    }

    func testDespiertoAntesDeDormirseNoCuentaEnLaEficiencia() {
        let t = f(cal, 3, 10, 23)
        let r = AnalisisSueno.sesiones(AnalisisSueno.unificar([m(t, 30, .despierto), m(t.addingTimeInterval(1800), 420, .nucleo)], ahora: f(cal, 3, 12, 0)), cal: cal)
        XCTAssertEqual(r[0].dormido, t.addingTimeInterval(1800))
        XCTAssertEqual(r[0].eficiencia, 1, accuracy: 0.001)
    }

    func testCambioDeHorarioUsaMinutosReales() {
        let ny = calendario("America/New_York")
        // Primavera: 22:00 → 06:00 pasa por las 2 → 3 am: son 7 h reales aunque el reloj marque 8.
        let p = AnalisisSueno.sesiones(AnalisisSueno.unificar([m(f(ny, 3, 7, 22), 420, .nucleo)], ahora: f(ny, 3, 9, 0)), cal: ny)
        XCTAssertEqual(p[0].minDormido, 420, accuracy: 0.01)
        XCTAssertEqual(ny.component(.hour, from: p[0].despierto), 6)
        XCTAssertEqual(p[0].dia, ny.startOfDay(for: f(ny, 3, 8, 12)))
        // Otoño: 22:00 → 06:00 son 9 h reales.
        let o = AnalisisSueno.sesiones(AnalisisSueno.unificar([m(f(ny, 10, 31, 22), 540, .nucleo)], ahora: f(ny, 11, 2, 0)), cal: ny)
        XCTAssertEqual(o[0].dia, ny.startOfDay(for: f(ny, 11, 1, 12)))
        XCTAssertEqual(o[0].minDormido, 540, accuracy: 0.01)
    }

    // MARK: Puntaje, regularidad, promedio, deuda

    private func noche(_ dia: Int, horas: Double, dormir: Int = 23, minutos: Double? = nil, etapas: Bool = true) -> ResumenNoche {
        let d = f(cal, 3, dormir < 12 ? dia : dia - 1, dormir)
        let min = minutos ?? horas * 60
        var n = ResumenNoche(dia: cal.startOfDay(for: f(cal, 3, dia, 12)), dormido: d, despierto: d.addingTimeInterval(min * 60))
        if etapas { n.minNucleo = min * 0.55; n.minProfundo = min * 0.2; n.minREM = min * 0.25 } else { n.minSinEtapa = min }
        return n
    }

    func testPuntajePerfectoYMalo() {
        XCTAssertEqual(AnalisisSueno.puntaje(noche(11, horas: 8), metaHoras: 8, desvDormir: 10).total, 100)
        var malo = noche(11, horas: 4); malo.minProfundo = 0; malo.minREM = 0; malo.minNucleo = 240; malo.minDespierto = 120; malo.despierto = malo.despierto.addingTimeInterval(7200)
        let p = AnalisisSueno.puntaje(malo, metaHoras: 8, desvDormir: 120)
        XCTAssertLessThan(p.total, 30)
        XCTAssertEqual(p.componentes.count, 4)
    }

    func testPuntajeSinEtapasNiRegularidadNoRegalaNiCastiga() {
        let p = AnalisisSueno.puntaje(noche(11, horas: 8, etapas: false), metaHoras: 8, desvDormir: nil)
        XCTAssertEqual(p.componentes.map(\.nombre), ["Duración", "Eficiencia"])
        XCTAssertEqual(p.total, 100)
        XCTAssertEqual(p.componentes.reduce(0) { $0 + $1.max }, 75)
    }

    func testPuntajeNoSePasaDe100AunDurmiendoDeMas() {
        XCTAssertEqual(AnalisisSueno.puntaje(noche(11, horas: 12), metaHoras: 8, desvDormir: 0).total, 100)
        XCTAssertEqual(AnalisisSueno.puntaje(noche(11, horas: 0), metaHoras: 8, desvDormir: nil).total, 0)   // sin dormir y sin división entre cero
    }

    func testRegularidad() {
        XCTAssertNil(AnalisisSueno.regularidad([noche(10, horas: 8), noche(11, horas: 8)], cal: cal))
        let igual = AnalisisSueno.regularidad([noche(10, horas: 8), noche(11, horas: 8), noche(12, horas: 8)], cal: cal)!
        XCTAssertEqual(igual.dormir, 0, accuracy: 0.001)
        // 23:30, 00:30, 23:30: la 1 am cuenta como 25:00, no como 24 h de diferencia.
        func a(_ h: Int, _ mi: Int, _ dia: Int) -> ResumenNoche {
            let d = f(cal, 3, dia, h, mi); return ResumenNoche(dia: cal.startOfDay(for: d.addingTimeInterval(8 * 3600)), dormido: d, despierto: d.addingTimeInterval(8 * 3600), minNucleo: 480)
        }
        let r = AnalisisSueno.regularidad([a(23, 30, 10), a(0, 30, 12), a(23, 30, 12)], cal: cal)!
        XCTAssertEqual(r.dormir, 28.28, accuracy: 0.1)
    }

    func testPromedioYDeuda() {
        let hoy = f(cal, 3, 12, 12)
        let ns = [noche(12, horas: 7), noche(11, horas: 8), noche(10, horas: 6), noche(1, horas: 9)]
        XCTAssertEqual(AnalisisSueno.promedioHoras(ns, dias: 7, hoy: hoy, cal: cal)!, 7, accuracy: 0.001)   // la del día 1 queda fuera
        XCTAssertEqual(AnalisisSueno.promedioHoras(ns, dias: 30, hoy: hoy, cal: cal)!, 7.5, accuracy: 0.001)
        let d = AnalisisSueno.deuda(ns, metaHoras: 8, hoy: hoy, cal: cal)
        XCTAssertEqual(d.horas, 3, accuracy: 0.001)           // 1 + 0 + 2
        XCTAssertEqual(d.noches, 3)
        XCTAssertNil(AnalisisSueno.promedioHoras([], dias: 7, hoy: hoy, cal: cal))
        let vacio = AnalisisSueno.deuda([], metaHoras: 8, hoy: hoy, cal: cal)
        XCTAssertEqual(vacio.horas, 0); XCTAssertEqual(vacio.noches, 0)
        var siesta = noche(12, horas: 1); siesta.siesta = true
        XCTAssertEqual(AnalisisSueno.deuda([siesta], metaHoras: 8, hoy: hoy, cal: cal).noches, 0)   // las siestas no son noches
    }

    // MARK: Registro manual

    func testValidarManual() {
        let t = ahora
        XCTAssertEqual(AnalisisSueno.validar(dormido: t, despierto: t, ahora: t), .orden)
        XCTAssertEqual(AnalisisSueno.validar(dormido: t, despierto: t.addingTimeInterval(-3600), ahora: t), .orden)
        XCTAssertEqual(AnalisisSueno.validar(dormido: t.addingTimeInterval(-21 * 3600), despierto: t.addingTimeInterval(-60), ahora: t), .larga)
        XCTAssertEqual(AnalisisSueno.validar(dormido: t.addingTimeInterval(-1200), despierto: t.addingTimeInterval(-60), ahora: t), .corta)
        XCTAssertEqual(AnalisisSueno.validar(dormido: t.addingTimeInterval(3600), despierto: t.addingTimeInterval(9 * 3600), ahora: t), .futuro)
        XCTAssertEqual(AnalisisSueno.validar(dormido: t.addingTimeInterval(-40 * 86400), despierto: t.addingTimeInterval(-40 * 86400 + 28800), ahora: t), .antigua)
        XCTAssertNil(AnalisisSueno.validar(dormido: t.addingTimeInterval(-9 * 3600), despierto: t.addingTimeInterval(-3600), ahora: t))
        XCTAssertNil(AnalisisSueno.validar(dormido: t.addingTimeInterval(-20 * 3600), despierto: t, ahora: t))   // justo 20 h
    }

    private var contenedor: ModelContainer!
    private func contexto() throws -> ModelContext {
        let esq = Schema([NocheSueno.self, MetricaDia.self, PesoLog.self])
        contenedor = try ModelContainer(for: esq, configurations: ModelConfiguration(schema: esq, isStoredInMemoryOnly: true))
        return ModelContext(contenedor)
    }

    func testRegistrarManualReemplazaYSaludGana() throws {
        let c = try contexto()
        let fin = Date().addingTimeInterval(-3600)
        try NocheSueno.registrarManual(dormido: fin.addingTimeInterval(-8 * 3600), despierto: fin, c)
        try NocheSueno.registrarManual(dormido: fin.addingTimeInterval(-7 * 3600), despierto: fin, c)       // mismo día: reemplaza
        var todas = try c.fetch(FetchDescriptor<NocheSueno>())
        XCTAssertEqual(todas.count, 1)
        XCTAssertEqual(NocheSueno.mejorPorDia(todas)[0].horasDormidas, 7, accuracy: 0.01)
        XCTAssertThrowsError(try NocheSueno.registrarManual(dormido: fin, despierto: fin.addingTimeInterval(-60), c))   // inválida: no guarda
        XCTAssertEqual(try c.fetch(FetchDescriptor<NocheSueno>()).count, 1)
        // Una noche de Salud ese mismo día gana a la manual.
        var r = ResumenNoche(dia: todas[0].dia, dormido: fin.addingTimeInterval(-6 * 3600), despierto: fin); r.minNucleo = 360
        c.insert(NocheSueno(r))
        todas = try c.fetch(FetchDescriptor<NocheSueno>())
        let mejor = NocheSueno.mejorPorDia(todas)
        XCTAssertEqual(mejor.count, 1)
        XCTAssertTrue(mejor[0].tieneEtapas)
    }

    func testResumenSobreviveElGuardado() throws {
        var r = ResumenNoche(dia: Date(), dormido: Date(timeIntervalSince1970: 0), despierto: Date(timeIntervalSince1970: 28800))
        r.minNucleo = 300; r.segmentos = [Segmento(inicio: r.dormido, fin: r.despierto, etapa: .nucleo)]
        let leido = NocheSueno(r).resumen
        XCTAssertEqual(leido.segmentos, r.segmentos); XCTAssertEqual(leido.minNucleo, 300)
    }

    // MARK: Servicio con proveedor falso

    func testSincronizarGuardaNochesMetricasYPesoSinPisarCapturas() async throws {
        let c = try contexto()
        let hoy = cal.startOfDay(for: ahora)
        let ayer = cal.date(byAdding: .day, value: -1, to: hoy)!
        c.insert(PesoLog(dia: hoy, kg: 76))                                           // captura manual de hoy
        var prov = ProveedorSaludFalso(ahora: ahora, cal: cal)
        prov.pesosFalsos = [(ayer, 75.2), (hoy, 80), (cal.date(byAdding: .day, value: -2, to: hoy)!, 5)]   // 5 kg = inválido
        let svc = SaludService(proveedor: prov)
        await svc.sincronizar(c, ahora: ahora, cal: cal)

        let noches = try c.fetch(FetchDescriptor<NocheSueno>())
        XCTAssertGreaterThanOrEqual(noches.filter { !$0.siesta }.count, 9)
        XCTAssertEqual(NocheSueno.mejorPorDia(noches).count, Set(noches.filter { !$0.siesta }.map(\.dia)).count)
        XCTAssertEqual(noches.filter(\.siesta).count, 1)
        XCTAssertFalse(try c.fetch(FetchDescriptor<MetricaDia>()).isEmpty)
        let pesos = try c.fetch(FetchDescriptor<PesoLog>())
        XCTAssertEqual(pesos.first { $0.dia == hoy }?.kg, 76)                          // no se pisó
        XCTAssertEqual(pesos.first { $0.dia == ayer }?.kg, 75.2)                       // se sembró
        XCTAssertEqual(pesos.count, 2)                                                  // el de 5 kg se rechazó

        let antes = noches.count
        await svc.sincronizar(c, ahora: ahora, cal: cal)                               // idempotente
        XCTAssertEqual(try c.fetch(FetchDescriptor<NocheSueno>()).count, antes)
        XCTAssertEqual(try c.fetch(FetchDescriptor<PesoLog>()).count, 2)
    }

    func testSincronizarSinDatosONoDisponibleNoBorraLaCache() async throws {
        let c = try contexto()
        var r = ResumenNoche(dia: cal.startOfDay(for: ahora), dormido: ahora.addingTimeInterval(-30000), despierto: ahora.addingTimeInterval(-1200)); r.minNucleo = 400
        c.insert(NocheSueno(r)); try c.save()
        var vacio = ProveedorSaludFalso(sueno: [], ahora: ahora, cal: cal)
        await SaludService(proveedor: vacio).sincronizar(c, ahora: ahora, cal: cal)
        XCTAssertEqual(try c.fetch(FetchDescriptor<NocheSueno>()).count, 1)
        vacio.disponible = false
        let svc = SaludService(proveedor: vacio)
        XCTAssertFalse(svc.disponible)
        await svc.sincronizar(c, ahora: ahora, cal: cal)
        XCTAssertEqual(try c.fetch(FetchDescriptor<NocheSueno>()).count, 1)
    }

    func testSincronizarConservaLasNochesManualesDeOtrosDias() async throws {
        let c = try contexto()
        let manual = ahora.addingTimeInterval(-86400 * 20)
        try NocheSueno.registrarManual(dormido: manual.addingTimeInterval(-8 * 3600), despierto: manual, c, ahora: ahora, cal: cal)
        await SaludService(proveedor: ProveedorSaludFalso(ahora: ahora, cal: cal)).sincronizar(c, ahora: ahora, cal: cal)
        XCTAssertEqual(try c.fetch(FetchDescriptor<NocheSueno>()).filter(\.manual).count, 1)
    }
}
