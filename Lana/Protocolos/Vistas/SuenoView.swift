import SwiftUI
import SwiftData
import Charts

extension EtapaSueno {
    var color: Color {
        switch self {
        case .despierto: .orange
        case .nucleo: .blue
        case .profundo: .indigo
        case .rem: .cyan
        case .sinEtapa: .teal
        case .enCama: .gray
        }
    }
}

struct SuenoView: View {
    @ObservedObject var salud: SaludService
    @Environment(\.modelContext) private var contexto
    @Environment(\.openURL) private var abrirURL
    @Query(sort: \NocheSueno.dia, order: .reverse) private var guardadas: [NocheSueno]
    @Query(sort: \MetricaDia.dia, order: .reverse) private var metricas: [MetricaDia]
    @AppStorage("protocolos.sueno.meta") private var meta = 8.0
    @AppStorage(Rampa.llaveSemana) private var semana = 1
    @AppStorage(Rampa.llaveRecordatorios) private var recordatorios = false
    @State private var registrando = false

    private var noches: [ResumenNoche] { NocheSueno.mejorPorDia(guardadas) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let ultima = noches.first {
                    tarjetaNoche(ultima)
                    tarjetaSemana
                    tarjetaRegularidad
                } else {
                    estadoVacio
                }
                tarjetaCuerpo
                siestas
                Button { registrando = true } label: { Label("Registrar noche manual", systemImage: "square.and.pencil").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).accessibilityIdentifier("sueno.manual")
                tarjetaRampa
                tarjetaRecordatorios
                pie
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { await salud.sincronizar(contexto) }
        .sheet(isPresented: $registrando) { NocheManualView() }
    }

    private func tarjeta<C: View>(_ titulo: String, @ViewBuilder _ contenido: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(titulo).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            contenido()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func dato(_ valor: String, _ etiqueta: String) -> some View {
        VStack(spacing: 2) {
            Text(valor).font(.headline.monospacedDigit())
            Text(etiqueta).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity)
    }

    // MARK: Anoche

    private func tarjetaNoche(_ n: ResumenNoche) -> some View {
        let p = AnalisisSueno.puntaje(de: n, entre: noches, metaHoras: meta)
        let esHoy = Calendar.current.isDateInToday(n.dia)
        let titulo = esHoy ? "Anoche" : "Última noche · " + n.dia.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        return tarjeta(titulo) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(minutosTexto(n.minDormido)).font(.system(size: 34, weight: .bold, design: .rounded))
                        .accessibilityIdentifier("sueno.anoche")
                    Text("\(n.dormido.formatted(date: .omitted, time: .shortened)) → \(n.despierto.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                AroPuntaje(total: p.total)
            }
            HStack {
                dato("\(Int((n.eficiencia * 100).rounded())) %", "Eficiencia")
                dato(minutosTexto(n.minDespierto), "Despierto")
                if n.tieneEtapas { dato(minutosTexto(n.minProfundo + n.minREM), "Profundo + REM") }
            }
            if n.tieneEtapas {
                HipnogramaView(noche: n)
                EtapasBarra(noche: n)
            } else {
                Text("Esta noche no trae etapas (se capturó a mano o sin Apple Watch).").font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("¿Cómo se calcula el puntaje?") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(p.componentes) { c in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack { Text(c.nombre).font(.subheadline.weight(.medium)); Spacer()
                                Text("\(Int(c.puntos.rounded())) / \(Int(c.max))").font(.subheadline.monospacedDigit()) }
                            ProgressView(value: c.puntos, total: c.max).tint(.green)
                            Text(c.detalle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("Lo que no se puede medir (por ejemplo etapas sin Watch) no cuenta ni a favor ni en contra.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(.top, 6)
            }.font(.subheadline)
        }
    }

    // MARK: Semana

    private var tarjetaSemana: some View {
        let prom7 = AnalisisSueno.promedioHoras(noches, dias: 7)
        let prom30 = AnalisisSueno.promedioHoras(noches, dias: 30)
        let d = AnalisisSueno.deuda(noches, metaHoras: meta)
        func h(_ x: Double?) -> String { x.map { String(format: "%.1f h", $0) } ?? "—" }
        return tarjeta("Tendencia") {
            HStack {
                dato(h(prom7), "Promedio 7 días")
                dato(h(prom30), "Promedio 30 días")
                dato(d.noches == 0 ? "—" : (d.horas < 0.05 ? "Sin deuda" : String(format: "%.1f h", d.horas)), "Deuda de sueño (7 d)")
            }
            Chart {
                ForEach(noches.prefix(14)) { n in
                    BarMark(x: .value("Día", n.dia, unit: .day), y: .value("Horas", n.horasDormidas))
                        .foregroundStyle(n.horasDormidas >= meta ? Color.green : Color.orange)
                }
                RuleMark(y: .value("Meta", meta)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(.secondary)
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { AxisValueLabel(format: .dateTime.day()) } }
            .frame(height: 120)
            Stepper(value: $meta, in: 6...10, step: 0.5) {
                Text("Meta: \(String(format: "%g", meta)) h por noche").font(.subheadline)
            }
        }
        .accessibilityIdentifier("sueno.semana")
    }

    private var tarjetaRegularidad: some View {
        let r = AnalisisSueno.regularidad(Array(noches.prefix(7)))
        func estado(_ m: Double) -> String { m <= 30 ? "Muy regular" : (m <= 60 ? "Regular" : "Irregular") }
        return tarjeta("Regularidad (7 noches)") {
            if let r {
                HStack {
                    dato("±\(Int(r.dormir.rounded())) min", "Hora de dormir\n\(estado(r.dormir))")
                    dato("±\(Int(r.despertar.rounded())) min", "Hora de despertar\n\(estado(r.despertar))")
                }
                Text("Dormir y despertar a la misma hora mejora más el descanso que dormir más horas un día suelto.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Necesito al menos 3 noches para medir tu regularidad.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Cuerpo (FC reposo, HRV, pasos, energía)

    private var tarjetaCuerpo: some View {
        let hoy = Calendar.current.startOfDay(for: Date())
        let deHoy = metricas.first { $0.dia == hoy }
        func ultimo(_ k: KeyPath<MetricaDia, Double?>) -> (v: Double, delta: Double?)? {
            guard let i = metricas.firstIndex(where: { $0[keyPath: k] != nil }), let v = metricas[i][keyPath: k] else { return nil }
            let previos = metricas.dropFirst(i + 1).prefix(7).compactMap { $0[keyPath: k] }
            return (v, previos.isEmpty ? nil : v - previos.reduce(0, +) / Double(previos.count))
        }
        func flecha(_ d: Double?, mejorBajo: Bool) -> String {
            guard let d, abs(d) >= 0.5 else { return "" }
            return (d > 0 ? " ▲" : " ▼") + String(format: "%.0f", abs(d))
        }
        let fc = ultimo(\.fcReposo), hrv = ultimo(\.hrv)
        return tarjeta("Cuerpo") {
            if metricas.isEmpty {
                Text("Aún no hay datos de tu Apple Watch (frecuencia en reposo, HRV, pasos).").font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack {
                    dato(fc.map { "\(Int($0.v.rounded()))\(flecha($0.delta, mejorBajo: true))" } ?? "—", "FC reposo (lpm)")
                    dato(hrv.map { "\(Int($0.v.rounded()))\(flecha($0.delta, mejorBajo: false))" } ?? "—", "HRV (ms)")
                    dato(deHoy?.pasos.map { Int($0).formatted() } ?? "—", "Pasos hoy")
                    dato(deHoy?.energia.map { "\(Int($0))" } ?? "—", "Kcal activas")
                }
                Text("▲▼ = contra tu promedio de los 7 días previos. FC en reposo más baja y HRV más alta suelen indicar mejor recuperación.")
                    .font(.caption2).foregroundStyle(.secondary)
                TendenciaMini(titulo: "FC en reposo", datos: serie(\.fcReposo), color: .red)
                TendenciaMini(titulo: "HRV", datos: serie(\.hrv), color: .green)
            }
        }
        .accessibilityIdentifier("sueno.cuerpo")
    }

    private func serie(_ k: KeyPath<MetricaDia, Double?>) -> [(Date, Double)] {
        var out: [(Date, Double)] = []
        for m in metricas.prefix(14) { if let v = m[keyPath: k] { out.append((m.dia, v)) } }
        return out
    }

    @ViewBuilder private var siestas: some View {
        let s = guardadas.filter(\.siesta).prefix(5)
        if !s.isEmpty {
            tarjeta("Siestas recientes") {
                ForEach(Array(s)) { n in
                    HStack {
                        Text(n.dormido.formatted(.dateTime.weekday(.abbreviated).day().hour().minute()))
                        Spacer()
                        Text(minutosTexto(n.minNucleo + n.minProfundo + n.minREM + n.minSinEtapa)).foregroundStyle(.secondary)
                    }.font(.subheadline)
                }
            }
        }
    }

    // MARK: Estado vacío

    private var estadoVacio: some View {
        tarjeta("Sueño") {
            VStack(spacing: 10) {
                Image(systemName: "moon.zzz.fill").font(.largeTitle).foregroundStyle(.indigo)
                Text(salud.cargando ? "Leyendo Salud…" : "Aún no hay sueño en Lana").font(.headline)
                if salud.cargando { ProgressView() }
                else if !salud.disponible {
                    Text("Salud no está disponible en este dispositivo (iPad o simulador). Puedes registrar tu sueño a mano abajo.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                } else {
                    Text("Lana lee el sueño que mide tu Apple Watch desde la app Salud. Si ya duermes con el reloj y no aparece, activa el permiso: Salud → tu foto → Apps → Lana → Sueño, o Ajustes → Salud → Acceso a datos y dispositivos → Lana.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    HStack {
                        Button("Abrir Ajustes") { if let u = URL(string: UIApplication.openSettingsURLString) { abrirURL(u) } }
                        Button("Reintentar") { Task { await salud.sincronizar(contexto) } }
                    }.buttonStyle(.bordered)
                }
            }.frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("sueno.vacio")
    }

    // MARK: Rampa + recordatorios (de antes)

    private var tarjetaRampa: some View {
        tarjeta("Rampa de sueño (despertar · dormir)") {
            ForEach(Rampa.pasos) { p in
                HStack {
                    Text("Semana \(p.semana)").fontWeight(p.semana == semana ? .bold : .regular)
                    Spacer()
                    Text("\(horaTexto(minutos: p.despertar)) · \(horaTexto(minutos: p.dormir))").foregroundStyle(.secondary)
                    if p.semana == semana { Image(systemName: "checkmark").foregroundStyle(.green) }
                }
                .font(.subheadline)
                .contentShape(Rectangle())
                .onTapGesture { cambiarSemana(p.semana) }
            }
            Text("Toca para cambiar de semana. No avances hasta lograr dormirte a tiempo la semana actual.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var tarjetaRecordatorios: some View {
        tarjeta("Recordatorios") {
            Toggle("Recordatorios", isOn: $recordatorios)
                .onChange(of: recordatorios) { _, activo in
                    Task { if activo { await Recordatorios.programar(paso: Rampa.paso(semana)) } else { await Recordatorios.apagar() } }
                }
            Text("Despertar, gym, corte de cafeína, cena, estudio, modo fin de día y hora de dormir, según la semana de la rampa.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var pie: some View {
        VStack(spacing: 4) {
            if let u = salud.ultimaSync { Text("Salud actualizado \(u.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.secondary) }
            Text("Estimaciones de tu reloj, no un diagnóstico. Si te sigue costando dormir tras varias semanas de buenos hábitos, consulta a un médico.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private func cambiarSemana(_ nueva: Int) {
        semana = nueva
        if recordatorios { Task { await Recordatorios.programar(paso: Rampa.paso(nueva)) } }
    }
}
