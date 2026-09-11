import WidgetKit
import SwiftUI
import SwiftData
import AppIntents

// MARK: - Datos que alimentan al widget

struct CategoriaResumen: Identifiable {
    let id = UUID()
    let nombre: String
    let emoji: String
    let colorHex: String
    let total: Double
}

struct EntradaLana: TimelineEntry {
    let date: Date
    let gastoMes: Double
    let categorias: [CategoriaResumen]
    let invertido: Double
    let rendimientoMensual: Double
    let tasaPromedio: Double

    static let muestra = EntradaLana(
        date: Date(),
        gastoMes: 7_566,
        categorias: [
            CategoriaResumen(nombre: "Ropa", emoji: "👕", colorHex: "#5E5CE6", total: 2_400),
            CategoriaResumen(nombre: "Casa", emoji: "🏠", colorHex: "#AC8E68", total: 1_580),
            CategoriaResumen(nombre: "Súper", emoji: "🛒", colorHex: "#30D158", total: 1_240)
        ],
        invertido: 110_271,
        rendimientoMensual: 1_336,
        tasaPromedio: 14.5
    )
}

struct ProveedorLana: TimelineProvider {
    func placeholder(in context: Context) -> EntradaLana { .muestra }

    func getSnapshot(in context: Context, completion: @escaping (EntradaLana) -> Void) {
        completion(context.isPreview ? .muestra : leer())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EntradaLana>) -> Void) {
        let entrada = leer()
        // Se refresca cada hora; los movimientos nuevos lo despiertan antes.
        let siguiente = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entrada], policy: .after(siguiente)))
    }

    /// Contexto propio: el widget no corre en el hilo principal de la app.
    private func leer() -> EntradaLana {
        let contexto = ModelContext(ContenedorLana.compartido)
        let movimientos = (try? contexto.fetch(FetchDescriptor<Movimiento>())) ?? []
        let cuentas = (try? contexto.fetch(FetchDescriptor<Cuenta>())) ?? []

        let delMes = Finanzas.movimientos(movimientos, en: Finanzas.rangoDelMes(de: Date()))
        let categorias = Finanzas.gastosPorCategoria(delMes).prefix(3).map {
            CategoriaResumen(nombre: $0.nombre, emoji: $0.emoji, colorHex: $0.colorHex, total: $0.total)
        }

        let invertidas = cuentas.filter { $0.activa && $0.rendimientoAnual > 0 }
        let invertido = invertidas.reduce(0.0) { $0 + max(0, Finanzas.saldo(de: $1, movimientos: movimientos)) }
        let tasa = Finanzas.tasaPonderada(cuentas: cuentas, movimientos: movimientos)

        return EntradaLana(
            date: Date(),
            gastoMes: Finanzas.totalGastos(delMes),
            categorias: Array(categorias),
            invertido: invertido,
            rendimientoMensual: Finanzas.rendimiento(saldo: invertido, tasaAnual: tasa, dias: 365) / 12,
            tasaPromedio: tasa
        )
    }
}

// MARK: - Widget de gastos

struct VistaGasto: View {
    @Environment(\.widgetFamily) private var familia
    let entrada: EntradaLana

    var body: some View {
        switch familia {
        case .systemMedium: mediano
        case .accessoryRectangular: rectangular
        default: chico
        }
    }

    private var chico: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(nombreMes(entrada.date).split(separator: " ").first.map(String.init) ?? "")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                botonAgregar
            }

            Spacer(minLength: 4)

            Text("Gastado")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(pesosCortos(entrada.gastoMes))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            if let top = entrada.categorias.first {
                HStack(spacing: 3) {
                    Text(top.emoji).font(.caption2)
                    Text(top.nombre)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.top, 2)
            }
        }
    }

    private var mediano: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(nombreMes(entrada.date))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                Text("Gastado")
                    .font(.caption2).foregroundStyle(.secondary)
                Text(pesosCortos(entrada.gastoMes))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Spacer(minLength: 6)
                botonAgregar
            }

            VStack(alignment: .leading, spacing: 7) {
                if entrada.categorias.isEmpty {
                    Text("Sin gastos este mes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entrada.categorias) { c in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Text(c.emoji).font(.caption2)
                                Text(c.nombre).font(.caption2).lineLimit(1)
                                Spacer()
                                Text(pesosCortos(c.total))
                                    .font(.caption2.weight(.semibold))
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(.quaternary).frame(height: 4)
                                    Capsule()
                                        .fill(Color(hex: c.colorHex))
                                        .frame(width: max(3, geo.size.width * proporcion(c)), height: 4)
                                }
                            }
                            .frame(height: 4)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Gastado este mes").font(.caption2)
            Text(pesosCortos(entrada.gastoMes)).font(.headline)
        }
    }

    private func proporcion(_ c: CategoriaResumen) -> Double {
        let mayor = entrada.categorias.map(\.total).max() ?? 1
        return mayor > 0 ? c.total / mayor : 0
    }

    private var botonAgregar: some View {
        Button(intent: AbrirCapturaIntent()) {
            HStack(spacing: 3) {
                Image(systemName: "plus.circle.fill")
                Text("Registrar").font(.caption2.weight(.medium))
            }
            .foregroundStyle(.green)
        }
        .buttonStyle(.plain)
    }
}

struct WidgetGasto: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LanaGasto", provider: ProveedorLana()) { entrada in
            VistaGasto(entrada: entrada)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Gasto del mes")
        .description("Cuánto llevas gastado y en qué, con botón para registrar.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

// MARK: - Widget de inversiones

struct VistaInversion: View {
    @Environment(\.widgetFamily) private var familia
    let entrada: EntradaLana

    var body: some View {
        if familia == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 1) {
                Text("Mi lana").font(.caption2)
                Text(pesosCortos(entrada.invertido)).font(.headline)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("Invertido")
                    .font(.caption2).foregroundStyle(.secondary)
                Text(pesosCortos(entrada.invertido))
                    .font(.system(size: familia == .systemMedium ? 34 : 26, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Spacer(minLength: 6)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right").font(.caption2)
                    Text("+\(pesos(entrada.rendimientoMensual, decimales: false)) al mes")
                        .font(.caption.weight(.semibold))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .foregroundStyle(.green)

                Text("a \(porcentaje(entrada.tasaPromedio)) anual")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct WidgetInversion: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LanaInversion", provider: ProveedorLana()) { entrada in
            VistaInversion(entrada: entrada)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Mis inversiones")
        .description("Cuánto tienes invertido y cuánto te está generando.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

// MARK: - Control de Centro de Control / pantalla bloqueada

struct ControlCaptura: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LanaControlCaptura") {
            ControlWidgetButton(action: AbrirCapturaIntent()) {
                Label("Registrar gasto", systemImage: "plus.circle.fill")
            }
        }
        .displayName("Registrar gasto")
        .description("Abre Lana listo para capturar.")
    }
}

@main
struct LanaWidgets: WidgetBundle {
    var body: some Widget {
        WidgetGasto()
        WidgetInversion()
        ControlCaptura()
    }
}
