import SwiftUI
import SwiftData

/// Pantalla de inicio: gasto del mes + gym + comida + protocolo de hoy.
/// Los datos de Protocolos viven en otra base, por eso van en una subvista con su propio contenedor.
struct PanelView: View {
    var irA: (Int) -> Void
    var capturar: () -> Void
    @Query private var movimientos: [Movimiento]
    @Query(sort: \Cuenta.orden) private var cuentas: [Cuenta]

    private var gastoMes: Double { Finanzas.totalGastos(Finanzas.movimientos(movimientos, en: Finanzas.rangoDelMes(de: Date()))) }
    private var gastoPasadoMismoPunto: Double {
        let c = Calendar.current
        guard let ant = c.date(byAdding: .month, value: -1, to: Date()) else { return 0 }
        let r = Finanzas.rangoDelMes(de: ant)
        let hasta = min(c.date(byAdding: .month, value: -1, to: Date()) ?? r.upperBound, r.upperBound)
        return Finanzas.totalGastos(Finanzas.movimientos(movimientos, en: r.lowerBound...hasta))
    }
    private var patrimonio: Double { Finanzas.patrimonio(cuentas: cuentas, movimientos: movimientos) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    PanelProtocolos(irA: irA, capturar: capturar, gasto: tarjetaGasto)
                        .modelContainer(ContenedorProtocolos.compartido)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)).prefix(1).uppercased() + Date().formatted(.dateTime.weekday(.wide).day().month(.wide)).dropFirst())
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var tarjetaGasto: some View {
        let dif = gastoMes - gastoPasadoMismoPunto
        return Button { irA(0) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Gasto de \(Date().formatted(.dateTime.month(.wide)))", systemImage: "creditcard.fill")
                        .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                Text(pesos(gastoMes, decimales: false))
                    .font(.system(size: 38, weight: .bold, design: .rounded)).foregroundStyle(.primary)
                HStack {
                    if gastoPasadoMismoPunto > 0 {
                        Label("\(pesos(abs(dif), decimales: false)) \(dif > 0 ? "más" : "menos") que a esta fecha el mes pasado",
                              systemImage: dif > 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption).foregroundStyle(dif > 0 ? .orange : .green)
                    }
                    Spacer()
                    Text("Patrimonio \(pesosCortos(patrimonio))").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre el resumen de finanzas")
    }
}

private struct PanelProtocolos<Gasto: View>: View {
    var irA: (Int) -> Void
    var capturar: () -> Void
    let gasto: Gasto
    @Environment(\.modelContext) private var contexto
    @Query private var definiciones: [EjercicioDef]
    @Query private var rutinas: [Rutina]
    @State private var sesionActiva: SesionGym?
    @State private var agregandoComida = false
    @Query private var logs: [HabitoLog]
    @Query private var comidas: [ComidaLog]
    @Query private var aguas: [AguaLog]
    @Query(sort: \SesionGym.inicio, order: .reverse) private var sesiones: [SesionGym]
    @AppStorage(LlavesMetas.kcal) private var metaKcal = 0.0
    @AppStorage(LlavesMetas.proteina) private var metaProteina = 0.0
    @AppStorage(LlavesMetas.agua) private var metaAgua = 3000.0
    @AppStorage(Programa.llave) private var semanaPrograma = 0
    @AppStorage(Rampa.llaveSemana) private var semanaSueno = 1
    @AppStorage("protocolos.seccion") private var seccion = "hoy"

    private var hoy: Date { Calendar.current.startOfDay(for: Date()) }
    private func ir(_ s: String) { seccion = s; irA(5) }

    var body: some View {
        VStack(spacing: 14) {
            accionesRapidas
            gasto
            gym
            comida
            protocolo
        }
        .fullScreenCover(item: $sesionActiva) { EntrenamientoActivoView(sesion: $0) }
        .sheet(isPresented: $agregandoComida) {
            AgregarAlimentoView(tiempo: tiempoActual, dia: hoy)
        }
        .task { Programa.sincronizar(contexto) }
    }

    private var tiempoActual: TiempoComida {
        switch Calendar.current.component(.hour, from: Date()) {
        case ..<11: .desayuno
        case ..<16: .comida
        case ..<19: .snack
        default: .cena
        }
    }

    // MARK: Acciones rápidas
    private var accionesRapidas: some View {
        let enCurso = sesiones.first { $0.fin == nil }
        return HStack(spacing: 10) {
            boton("Gasto", "plus.circle.fill", .green, capturar)
            boton(enCurso == nil ? "Entrenar" : "Continuar", "dumbbell.fill", .green) {
                if let s = enCurso { sesionActiva = s; return }
                let n = Programa.rutinaDe(Date())
                sesionActiva = iniciarSesion(rutina: rutinas.first { $0.nombre == n }, contexto: contexto,
                                             historial: sesiones, definiciones: definiciones)
            }
            boton("Comida", "fork.knife", .orange) { agregandoComida = true }
            boton("Agua +250", "drop.fill", .blue) {
                contexto.insert(AguaLog(dia: hoy, ml: 250)); try? contexto.save()
            }
            .contextMenu {
                Button("Quitar 250 ml", systemImage: "minus.circle") {
                    let hay = aguas.filter { $0.dia == hoy }.reduce(0) { $0 + $1.ml }
                    if hay > 0 { contexto.insert(AguaLog(dia: hoy, ml: -min(250, hay))); try? contexto.save() }
                }
                Button("Poner agua en 0", systemImage: "arrow.counterclockwise", role: .destructive) {
                    aguas.filter { $0.dia == hoy }.forEach(contexto.delete); try? contexto.save()
                }
            }
        }
    }

    private func boton(_ titulo: String, _ icono: String, _ color: Color, _ accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            VStack(spacing: 6) {
                Image(systemName: icono).font(.title2)
                Text(titulo).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: Gym
    private var gym: some View {
        let cal = Calendar.current
        let inicioSemana = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? hoy
        let terminadas = sesiones.filter { $0.fin != nil }
        let estaSemana = terminadas.filter { $0.inicio >= inicioSemana }.count
        let toca = Programa.rutinaDe(Date()).map { $0.replacingOccurrences(of: "BTS ", with: "") }
        let meta = semanaPrograma > 0 ? 5 : 4
        let ultima = terminadas.first
        return tarjeta("Gym", icono: "dumbbell.fill", color: .green, destino: "gym") {
            HStack(alignment: .firstTextBaseline) {
                Text(sesiones.contains { $0.fin == nil } ? "Entrenamiento en curso"
                     : (toca.map { "Hoy toca \($0)" } ?? "Hoy descansas"))
                    .font(.title3.weight(.bold))
                Spacer()
                Text("\(estaSemana)/\(meta) esta semana").font(.subheadline.weight(.semibold)).foregroundStyle(.green)
            }
            ProgressView(value: min(Double(estaSemana), Double(meta)), total: Double(meta)).tint(.green)
            Text([semanaPrograma > 0 ? "Programa: semana \(semanaPrograma) de 12" : nil,
                  ultima.map { "Última: \($0.nombre), \($0.inicio.formatted(.relative(presentation: .named)))" }]
                    .compactMap { $0 }.joined(separator: " · ").nilSiVacio ?? "Aún sin entrenamientos")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Comida
    private var comida: some View {
        let t = TotalesDia(comidas.filter { $0.dia == hoy })
        let agua = aguas.filter { $0.dia == hoy }.reduce(0) { $0 + $1.ml }
        return tarjeta("Comida", icono: "fork.knife", color: .orange, destino: "comida") {
            HStack(spacing: 18) {
                anillo(t.kcal, metaKcal, color: .orange, etiqueta: "kcal")
                VStack(alignment: .leading, spacing: 8) {
                    barra("Proteína", t.proteina, metaProteina, "g", .red)
                    barra("Agua", agua, metaAgua, "ml", .blue)
                }
            }
            if metaKcal == 0 { Text("Calcula tus metas en Comida → Metas").font(.caption).foregroundStyle(.secondary) }
        }
    }

    // MARK: Protocolo
    private var protocolo: some View {
        let habitos = Habito.allCases.filter { $0.aplica(en: Date()) }
        let hechos = Set(logs.filter { $0.dia == hoy }.map(\.clave)).intersection(habitos.map(\.rawValue)).count
        let paso = Rampa.paso(semanaSueno)
        return tarjeta("Protocolo de hoy", icono: "checklist", color: .purple, destino: "hoy") {
            HStack(spacing: 18) {
                anillo(Double(hechos), Double(habitos.count), color: .purple, etiqueta: "hábitos", entero: true)
                VStack(alignment: .leading, spacing: 6) {
                    Label("Acuéstate a las \(horaTexto(minutos: paso.dormir))", systemImage: "bed.double.fill").font(.subheadline)
                    Text("Sueño: semana \(semanaSueno) de la rampa").font(.caption).foregroundStyle(.secondary)
                    if hechos < habitos.count {
                        Text("Faltan: " + habitos.filter { h in !logs.contains { $0.dia == hoy && $0.clave == h.rawValue } }.prefix(2).map(\.nombre).joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    } else { Text("Todo hecho 🎉").font(.caption).foregroundStyle(.green) }
                }
            }
        }
    }

    // MARK: Piezas
    private func tarjeta<C: View>(_ titulo: String, icono: String, color: Color, destino: String,
                                  @ViewBuilder _ contenido: () -> C) -> some View {
        Button { ir(destino) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(titulo, systemImage: icono).font(.footnote.weight(.semibold)).foregroundStyle(color)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                contenido()
            }
            .padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre \(titulo)")
    }

    private func anillo(_ valor: Double, _ meta: Double, color: Color, etiqueta: String, entero: Bool = false) -> some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: 10)
            Circle().trim(from: 0, to: meta > 0 ? min(valor / meta, 1) : 0)
                .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(meta > 0 && entero ? "\(Int(valor))/\(Int(meta))" : "\(Int(valor))").font(.headline.monospacedDigit())
                Text(meta > 0 && !entero ? "de \(Int(meta)) \(etiqueta)" : etiqueta).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 96, height: 96)
    }

    private func barra(_ nombre: String, _ valor: Double, _ meta: Double, _ unidad: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(nombre).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(meta > 0 ? "\(Int(valor)) / \(Int(meta)) \(unidad)" : "\(Int(valor)) \(unidad)").font(.caption.monospacedDigit())
            }
            ProgressView(value: meta > 0 ? min(valor, meta) : 0, total: max(meta, 1)).tint(color)
        }
    }
}

private extension String { var nilSiVacio: String? { isEmpty ? nil : self } }
