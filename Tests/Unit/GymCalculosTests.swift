import XCTest
import SwiftData
@testable import Lana

@MainActor
final class GymCalculosTests: XCTestCase {
    private let nombre = "Press de banca con barra"

    private func contexto() throws -> ModelContext {
        let esquema = Schema([HabitoLog.self, EjercicioDef.self, Rutina.self, SesionGym.self, EjercicioLog.self,
                              Serie.self, Alimento.self, ComidaLog.self, AguaLog.self])
        let c = try ModelContainer(for: esquema, configurations: ModelConfiguration(schema: esquema, isStoredInMemoryOnly: true))
        return ModelContext(c)
    }

    @discardableResult
    private func sesion(_ ctx: ModelContext, dias: Int, series: [(Double, Int, TipoSerie)], fin: Bool = true) -> SesionGym {
        let s = SesionGym(nombre: "T")
        ctx.insert(s)
        s.inicio = Calendar.current.date(byAdding: .day, value: -dias, to: Date())!
        s.fin = fin ? s.inicio.addingTimeInterval(3600) : nil
        let e = EjercicioLog(nombre: nombre, grupo: "Pecho", orden: 0)
        ctx.insert(e); e.sesion = s
        for (i, x) in series.enumerated() {
            let sr = Serie(orden: i, peso: x.0, reps: x.1, tipo: x.2)
            sr.hecha = true
            ctx.insert(sr); sr.ejercicio = e
        }
        return s
    }

    private func vivos(_ s: SesionGym, _ h: [SesionGym]) -> [[TipoRecord]] {
        let e = s.ejerciciosOrdenados[0]
        let previas = GymCalculos.marcasPrevias(de: nombre, historial: h, antesDe: s.inicio, excepto: s)
        return e.seriesOrdenadas.map { GymCalculos.records(de: $0, en: e, previas: previas) }
    }

    func testPrimeraVezEsLineaBaseSinRecords() throws {
        let ctx = try contexto()
        let s = sesion(ctx, dias: 0, series: [(100, 5, .normal), (110, 5, .normal)], fin: false)
        XCTAssertNil(GymCalculos.marcasPrevias(de: nombre, historial: [s], antesDe: s.inicio, excepto: s))
        XCTAssertTrue(vivos(s, [s]).allSatisfy(\.isEmpty))
    }

    func testRecordEnVivoYSegundaSerieIgualNoSeRepite() throws {
        let ctx = try contexto()
        let vieja = sesion(ctx, dias: 7, series: [(100, 5, .normal)])
        let hoy = sesion(ctx, dias: 0, series: [(105, 5, .normal), (105, 5, .normal), (107.5, 5, .normal)], fin: false)
        let r = vivos(hoy, [hoy, vieja])
        XCTAssertTrue(r[0].contains(.peso) && r[0].contains(.e1rm) && r[0].contains(.volumen))
        XCTAssertTrue(r[1].isEmpty, "la misma marca no cuenta dos veces")
        XCTAssertTrue(r[2].contains(.peso), "una marca mayor sí es récord otra vez")
    }

    func testCalentamientoNoCuentaNiEnVivoNiEnResumen() throws {
        let ctx = try contexto()
        let vieja = sesion(ctx, dias: 7, series: [(100, 5, .normal)])
        let hoy = sesion(ctx, dias: 0, series: [(200, 5, .calentamiento), (90, 5, .normal)])
        XCTAssertTrue(vivos(hoy, [hoy, vieja]).allSatisfy(\.isEmpty))
        XCTAssertTrue(GymCalculos.records(de: hoy, historial: [hoy, vieja]).isEmpty)
        // y un calentamiento pasado no sube la vara
        let viejaConWarm = sesion(ctx, dias: 14, series: [(300, 5, .calentamiento), (80, 5, .normal)])
        let m = GymCalculos.marcasPrevias(de: nombre, historial: [viejaConWarm], antesDe: Date())
        XCTAssertEqual(m?.peso, 80)
    }

    func testRepsRecordSoloSiYaUsasEsePeso() throws {
        let ctx = try contexto()
        let vieja = sesion(ctx, dias: 7, series: [(100, 5, .normal)])
        let mas = sesion(ctx, dias: 0, series: [(100, 6, .normal)])
        let r = GymCalculos.records(de: mas, historial: [mas, vieja])
        XCTAssertTrue(r.contains { $0.tipo == .reps && $0.detalle.contains("6 con 100 kg (antes 5)") })
        let otroPeso = sesion(ctx, dias: 0, series: [(90, 12, .normal)])
        XCTAssertFalse(GymCalculos.records(de: otroPeso, historial: [otroPeso, vieja]).contains { $0.tipo == .reps })
    }

    func testDesmarcarQuitaElRecord() throws {
        let ctx = try contexto()
        let vieja = sesion(ctx, dias: 7, series: [(100, 5, .normal)])
        let hoy = sesion(ctx, dias: 0, series: [(105, 5, .normal)], fin: false)
        XCTAssertFalse(vivos(hoy, [hoy, vieja])[0].isEmpty)
        hoy.ejerciciosOrdenados[0].seriesOrdenadas[0].hecha = false
        XCTAssertTrue(vivos(hoy, [hoy, vieja])[0].isEmpty)
    }

    func testRecordsDeSesionPasadaSoloMiranLoAnterior() throws {
        let ctx = try contexto()
        let a = sesion(ctx, dias: 14, series: [(100, 5, .normal)])
        let b = sesion(ctx, dias: 7, series: [(110, 5, .normal)])
        let c = sesion(ctx, dias: 0, series: [(120, 5, .normal)])
        XCTAssertTrue(GymCalculos.records(de: a, historial: [c, b, a]).isEmpty, "la primera es línea base aunque luego hayas mejorado")
        XCTAssertTrue(GymCalculos.records(de: b, historial: [c, b, a]).contains { $0.tipo == .peso && $0.detalle.contains("antes 100") })
    }

    func testAnteriorExcluyeCalentamientos() throws {
        let ctx = try contexto()
        let vieja = sesion(ctx, dias: 7, series: [(40, 8, .calentamiento), (100, 5, .normal), (100, 4, .normal)])
        let a = GymCalculos.anterior(de: nombre, en: [vieja])
        XCTAssertEqual(a.map(\.peso), [100, 100])
    }
}
