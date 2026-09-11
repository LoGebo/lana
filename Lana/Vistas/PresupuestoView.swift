import SwiftUI
import SwiftData

struct PresupuestoView: View {
    @Environment(\.modelContext) private var contexto
    @Query(sort: \Categoria.orden) private var categorias: [Categoria]
    @Query private var movimientos: [Movimiento]
    @Query private var suscripciones: [Suscripcion]
    @Query(sort: \Cuenta.orden) private var cuentas: [Cuenta]

    /// Lo que te entra al mes. Vive en el grupo compartido para que el widget también lo vea.
    @AppStorage("lana.ingresoMensual", store: UserDefaults(suiteName: grupoLana))
    private var ingresoMensual: Double = 0

    @AppStorage("lana.metaAhorro", store: UserDefaults(suiteName: grupoLana))
    private var metaAhorro: Double = 0

    @State private var quincenaActiva = Nomina.activa
    @State private var creandoCategoria = false

    // MARK: - Números

    private var rango: ClosedRange<Date> { Finanzas.rangoDelMes(de: Date()) }
    private var delMes: [Movimiento] { Finanzas.movimientos(movimientos, en: rango) }
    private var gastadoReal: Double { Finanzas.totalGastos(delMes) }
    private var ingresoReal: Double { Finanzas.totalIngresos(delMes) }

    private var rendimientoMensual: Double {
        Finanzas.rendimientoDeHoy(cuentas: cuentas, movimientos: movimientos) * 30.4
    }

    private var totalEntra: Double { ingresoMensual + rendimientoMensual }
    private var fijosMensuales: Double { Finanzas.costoMensualTotal(suscripciones) }

    private var categoriasGasto: [Categoria] { categorias.filter { !$0.esIngreso } }
    private var totalPresupuestado: Double {
        categoriasGasto.reduce(0) { $0 + $1.presupuestoMensual }
    }

    private var libre: Double { totalEntra - fijosMensuales - totalPresupuestado - metaAhorro }

    private func gastadoEn(_ categoria: Categoria) -> Double {
        delMes.filter { $0.tipo == .gasto && $0.categoria?.id == categoria.id }
            .reduce(0) { $0 + $1.monto }
    }

    private var conPresupuesto: [Categoria] {
        categoriasGasto.filter { $0.presupuestoMensual > 0 }
            .sorted { $0.presupuestoMensual > $1.presupuestoMensual }
    }

    private var sinPresupuesto: [Categoria] {
        categoriasGasto.filter { $0.presupuestoMensual == 0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    tarjetaEntra
                    tarjetaQuincena
                    tarjetaCuadre
                    tarjetaFijos
                    tarjetaCategorias
                    tarjetaSinPresupuesto
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Presupuesto")
            .scrollDismissesKeyboard(.immediately)
            .sheet(isPresented: $creandoCategoria) {
                NavigationStack { EditorCategoriaView() }
            }
        }
    }

    // MARK: - Lo que entra

    private var tarjetaEntra: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("Te entra al mes")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(pesos(totalEntra, decimales: false))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
            }

            Divider()

            HStack {
                Text("💼 Sueldo / ingresos")
                    .font(.subheadline)
                Spacer()
                CampoMonto(valor: $ingresoMensual, ancho: 120)
                    .font(.subheadline.weight(.semibold))
            }

            if rendimientoMensual > 0 {
                HStack {
                    Text("📈 Rendimientos")
                        .font(.subheadline)
                    Spacer()
                    Text(pesos(rendimientoMensual, decimales: false))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            if ingresoReal > 0 {
                Divider()
                HStack {
                    Text("Registrado este mes")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(pesos(ingresoReal, decimales: false))
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Quincena automática

    private var tarjetaQuincena: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(
                get: { quincenaActiva },
                set: { prender($0) }
            )) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Color.green.opacity(0.18)).frame(width: 34, height: 34)
                        Image(systemName: "calendar.badge.clock").foregroundStyle(.green)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Quincena automática").font(.subheadline.weight(.medium))
                        Text("El 15 y el 30 de cada mes").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if quincenaActiva {
                Divider()

                if ingresoMensual <= 0 {
                    Text("Pon arriba tu sueldo mensual para saber de cuánto es cada quincena.")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    HStack {
                        Text("Cada quincena").font(.subheadline)
                        Spacer()
                        Text("+" + pesos(ingresoMensual / 2, decimales: false))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }

                Picker("Entra a", selection: Binding(
                    get: { cuentaQuincena?.id ?? UUID() },
                    set: { nuevo in Nomina.cuentaID = nuevo }
                )) {
                    ForEach(cuentas.filter(\.activa)) { c in
                        Text(c.nombre).tag(c.id)
                    }
                }
                .font(.subheadline)

                if let proxima = Nomina.siguientePago() {
                    Text("Próximo depósito: \(fechaCorta(proxima)). Si ese día no abres la app, se registra con su fecha correcta cuando la abras.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var cuentaQuincena: Cuenta? { Nomina.cuenta(entre: cuentas) }

    private func prender(_ activar: Bool) {
        Nomina.activa = activar
        quincenaActiva = activar
        if activar {
            // Arranca desde hoy: no queremos rellenar quincenas viejas.
            Nomina.desde = Date()
            if Nomina.cuentaID == nil { Nomina.cuentaID = cuentaQuincena?.id }
        }
    }

    // MARK: - Cómo cuadra el mes

    private var tarjetaCuadre: some View {
        VStack(spacing: 10) {
            renglon("Te entra", totalEntra, .green, signo: "+")
            renglon("Gastos fijos", fijosMensuales, .primary, signo: "−")
            renglon("Presupuestado", totalPresupuestado, .primary, signo: "−")

            HStack {
                Text("🐷 Meta de ahorro").font(.subheadline)
                Spacer()
                Text("−").foregroundStyle(.secondary)
                CampoMonto(valor: $metaAhorro, ancho: 110)
                    .font(.subheadline.weight(.semibold))
            }

            Divider()

            HStack {
                Text(libre >= 0 ? "Te sobra" : "Te falta")
                    .font(.headline)
                Spacer()
                Text(pesos(abs(libre), decimales: false))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(libre >= 0 ? .green : .red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }

            Text(libre >= 0
                 ? "Con este plan te queda holgura. Súbele a la meta de ahorro si quieres."
                 : "Estás presupuestando más de lo que te entra. Bájale a alguna categoría o a la meta.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func renglon(_ titulo: String, _ monto: Double, _ color: Color, signo: String) -> some View {
        HStack {
            Text(titulo).font(.subheadline)
            Spacer()
            Text(signo + pesos(monto, decimales: false))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    // MARK: - Fijos

    private var tarjetaFijos: some View {
        NavigationLink {
            SuscripcionesView()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.purple.opacity(0.18)).frame(width: 38, height: 38)
                    Image(systemName: "repeat").foregroundStyle(.purple)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Gastos fijos").font(.subheadline.weight(.medium))
                    Text("\(suscripciones.filter(\.activa).count) suscripciones activas")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(pesos(fijosMensuales, decimales: false))
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Presupuesto por categoría

    private var tarjetaCategorias: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Por categoría").font(.headline)
                    Spacer()
                    Text("llevas \(pesos(gastadoReal, decimales: false))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(textoReinicio)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if conPresupuesto.isEmpty {
                Text("Todavía no pones presupuestos. Ábrele abajo a las categorías y dale un tope a cada una.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(conPresupuesto) { c in
                    filaPresupuesto(c)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    /// El tope se queda igual mes con mes; lo que se reinicia es lo gastado.
    private var textoReinicio: String {
        let calendario = Calendar.current
        let finDeMes = Finanzas.rangoDelMes(de: Date()).upperBound
        let dias = calendario.dateComponents([.day], from: Date(), to: finDeMes).day ?? 0
        let siguiente = calendario.date(byAdding: .day, value: 1, to: finDeMes) ?? finDeMes
        let nombre = siguiente.formatted(.dateTime.month(.wide).locale(Locale(identifier: "es_MX")))
        switch dias {
        case 0: return "Tope mensual · el conteo se reinicia mañana con \(nombre)"
        case 1: return "Tope mensual · el conteo se reinicia en 1 día con \(nombre)"
        default: return "Tope mensual · el conteo se reinicia en \(dias) días con \(nombre)"
        }
    }

    private func filaPresupuesto(_ c: Categoria) -> some View {
        let gastado = gastadoEn(c)
        let tope = c.presupuestoMensual
        let avance = tope > 0 ? min(1.5, gastado / tope) : 0
        let pasado = gastado > tope

        return VStack(spacing: 6) {
            HStack {
                Text(c.emoji)
                Text(c.nombre).font(.subheadline)
                Spacer()
                Text(pesos(gastado, decimales: false))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(pasado ? .red : .primary)
                Text("/").foregroundStyle(.tertiary)
                CampoMonto(valor: Binding(
                    get: { c.presupuestoMensual },
                    set: { c.presupuestoMensual = $0; try? contexto.save() }
                ), ancho: 78)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill)).frame(height: 7)
                    Capsule()
                        .fill(pasado ? Color.red : Color(hex: c.colorHex))
                        .frame(width: max(4, geo.size.width * min(1, avance)), height: 7)
                }
            }
            .frame(height: 7)

            HStack {
                Text(pasado
                     ? "Te pasaste \(pesos(gastado - tope, decimales: false))"
                     : "Te quedan \(pesos(tope - gastado, decimales: false))")
                .font(.caption2)
                .foregroundStyle(pasado ? .red : .secondary)
                Spacer()
                Text(porcentaje(tope > 0 ? gastado / tope * 100 : 0, decimales: 0))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Categorías sin tope

    private var tarjetaSinPresupuesto: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sin presupuesto").font(.headline)
                Spacer()
                Button {
                    creandoCategoria = true
                } label: {
                    Label("Nueva", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.medium))
                }
            }
            Text("Ponles un tope mensual y aparecen arriba con su barra de avance. Para editar emoji, color o borrarlas: Ajustes → Categorías.")
                .font(.caption).foregroundStyle(.secondary)

            ForEach(sinPresupuesto) { c in
                HStack {
                    Text(c.emoji)
                    Text(c.nombre).font(.subheadline)
                    Spacer()
                    if gastadoEn(c) > 0 {
                        Text("llevas \(pesos(gastadoEn(c), decimales: false))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    CampoMonto(marcador: "poner", valor: Binding(
                        get: { c.presupuestoMensual },
                        set: { c.presupuestoMensual = $0; try? contexto.save() }
                    ), ancho: 80)
                    .font(.subheadline)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}
