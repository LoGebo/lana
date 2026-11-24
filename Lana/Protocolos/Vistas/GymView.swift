import SwiftUI
import SwiftData

struct GymView: View {
    @Environment(\.modelContext) private var contexto
    @Query(sort: \Rutina.orden) private var rutinas: [Rutina]
    @Query(sort: \SesionGym.inicio, order: .reverse) private var sesiones: [SesionGym]
    @Query private var definiciones: [EjercicioDef]

    @State private var activa: SesionGym?
    @State private var editando: Rutina?
    @State private var creando = false
    @State private var borrando: Rutina?

    private var enCurso: SesionGym? { sesiones.first { $0.fin == nil } }
    private var terminadas: [SesionGym] { sesiones.filter { $0.fin != nil } }

    private var rutinaDeHoy: Rutina? {
        let n = Programa.rutinaDe(Date())
        return rutinas.first { $0.nombre == n }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let s = enCurso { bannerEnCurso(s) }
                empezar
                tarjetaSemana
                TarjetaPrograma()
                tarjetaRutinas
                tarjetaHistorial
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .task { Programa.sincronizar(contexto) }
        .confirmationDialog("¿Borrar \(borrando?.nombre ?? "la rutina")?", isPresented: Binding(get: { borrando != nil }, set: { if !$0 { borrando = nil } }),
                            titleVisibility: .visible) {
            Button("Borrar rutina", role: .destructive) {
                if let r = borrando { contexto.delete(r); try? contexto.save() }
                borrando = nil
            }
        } message: { Text("Tus entrenamientos ya hechos no se borran.") }
        .fullScreenCover(item: $activa) { s in EntrenamientoActivoView(sesion: s) }
        .sheet(isPresented: $creando) { EditorRutinaView(rutina: nil) }
        .sheet(item: $editando) { r in EditorRutinaView(rutina: r) }
    }

    // MARK: - Piezas

    private func bannerEnCurso(_ s: SesionGym) -> some View {
        Button { activa = s } label: {
            HStack {
                Image(systemName: "figure.strengthtraining.traditional")
                VStack(alignment: .leading) {
                    Text("Entrenamiento en curso").font(.subheadline.weight(.semibold))
                    Text("\(s.nombre) · \(duracionTexto(s.duracion))").font(.caption)
                }
                Spacer()
                Text("Continuar").font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding()
            .background(Color.green, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private var empezar: some View {
        VStack(spacing: 10) {
            if let r = rutinaDeHoy, enCurso == nil {
                Button { empezar(rutina: r) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hoy toca").font(.caption)
                            Text(r.nombre).font(.title3.weight(.bold))
                        }
                        Spacer()
                        Image(systemName: "play.fill")
                    }
                    .foregroundStyle(.white)
                    .padding()
                    .background(Color.green, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
            }
            Button { empezar(rutina: nil) } label: {
                Label("Empezar entrenamiento vacío", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .disabled(enCurso != nil)
        }
    }

    // MARK: Resumen de la semana

    private var inicioSemana: Date { Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date() }
    private var estaSemana: [SesionGym] { terminadas.filter { $0.inicio >= inicioSemana } }

    /// Ejercicios en los que rompiste algún récord en esa sesión.
    // ponytail: recalcula contra todo el historial en cada render; con miles de sesiones, cachear en SesionGym.
    private func ejerciciosConRecord(_ s: SesionGym) -> Int {
        Set(GymCalculos.records(de: s, historial: sesiones).map(\.ejercicio)).count
    }

    private var tarjetaSemana: some View {
        let volumen = estaSemana.reduce(0) { $0 + $1.volumen }
        let series = estaSemana.reduce(0) { $0 + $1.seriesHechas.filter { $0.tipo.cuentaVolumen }.count }
        let records = estaSemana.reduce(0) { $0 + ejerciciosConRecord($1) }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Esta semana").font(.headline)
            HStack(spacing: 0) {
                dato("\(estaSemana.count)", "entrenos", "figure.strengthtraining.traditional", .green)
                dato(volumen >= 1000 ? String(format: "%.1f t", volumen / 1000) : "\(Int(volumen)) kg", "volumen", "scalemass.fill", .blue)
                dato("\(series)", "series", "list.number", .orange)
                dato("\(records)", "récords", "trophy.fill", .yellow)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Esta semana: \(estaSemana.count) entrenos, \(Int(volumen)) kilos de volumen, \(series) series, \(records) récords")
    }

    private func dato(_ valor: String, _ etiqueta: String, _ icono: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icono).font(.subheadline).foregroundStyle(color)
            Text(valor).font(.headline.monospacedDigit()).minimumScaleFactor(0.7).lineLimit(1)
            Text(etiqueta).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Rutinas

    /// Estimación: ~45 s por serie más el descanso del plan (90 s si no hay plan, 3 series).
    private func minutos(_ r: Rutina) -> Int {
        let plan = r.plan
        let seg = r.ejercicios.reduce(0.0) { acc, n in
            acc + Double(plan[n]?.series ?? 3) * (Double(plan[n]?.descanso ?? 90) + 45)
        }
        return max(5, Int((seg / 60 / 5).rounded()) * 5)
    }

    private var tarjetaRutinas: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Rutinas").font(.headline)
                Spacer()
                Button { creando = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                    .accessibilityLabel("Nueva rutina")
            }
            ForEach(rutinas) { r in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(r.nombre).font(.subheadline.weight(.semibold))
                        Text("\(r.ejercicios.count) ejercicios · ~\(minutos(r)) min")
                            .font(.caption.weight(.medium)).foregroundStyle(.green)
                        Text(r.ejercicios.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { empezar(rutina: r) } label: {
                        Image(systemName: "play.circle.fill").font(.title).foregroundStyle(enCurso == nil ? .green : .gray)
                    }
                    .buttonStyle(.plain)
                    .disabled(enCurso != nil)
                    .accessibilityLabel("Empezar \(r.nombre)")
                    Menu {
                        Button("Empezar", systemImage: "play.fill") { empezar(rutina: r) }.disabled(enCurso != nil)
                        Button("Editar", systemImage: "pencil") { editando = r }
                        Button("Borrar", systemImage: "trash", role: .destructive) { borrando = r }
                    } label: { Image(systemName: "ellipsis.circle").font(.title3).padding(4) }
                    .accessibilityLabel("Más opciones de \(r.nombre)")
                }
                .padding(.vertical, 4)
                if r.id != rutinas.last?.id { Divider() }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    // MARK: Historial

    private var tarjetaHistorial: some View {
        let recientes = Array(terminadas.prefix(15))
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Historial").font(.headline)
                Spacer()
                NavigationLink { ProgresoView() } label: {
                    Label("Progreso y ejercicios", systemImage: "chart.line.uptrend.xyaxis").font(.subheadline)
                }
            }
            if terminadas.isEmpty {
                Text("Aún no has terminado ningún entrenamiento.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(recientes) { s in
                let prs = ejerciciosConRecord(s)
                NavigationLink { DetalleSesionView(sesion: s) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(s.nombre).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            if prs > 0 {
                                Label("\(prs)", systemImage: "trophy.fill").font(.caption.weight(.bold))
                                    .foregroundStyle(.yellow)
                                    .accessibilityLabel("\(prs) ejercicios con récord")
                            }
                            Spacer()
                            Text(s.inicio.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("\(duracionTexto(s.duracion)) · \(numeroLimpio(s.volumen)) kg · \(s.seriesHechas.count) series")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                if s.id != recientes.last?.id { Divider() }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Acciones

    private func empezar(rutina: Rutina?) {
        activa = iniciarSesion(rutina: rutina, contexto: contexto, historial: sesiones, definiciones: definiciones)
    }
}

/// Agrega un ejercicio a la sesión. Si la rutina trae plan, usa sus series y descanso,
/// y pone los pesos de la última vez (sin marcar).
func agregarEjercicio(nombre: String, grupo: String, a sesion: SesionGym, orden: Int,
                      contexto: ModelContext, historial: [SesionGym], plan: ItemPlan? = nil) {
    let e = EjercicioLog(nombre: nombre, grupo: grupo.isEmpty ? (plan?.grupo ?? "") : grupo, orden: orden,
                         descansoSeg: plan?.descanso ?? 90)
    if let p = plan {
        e.objetivo = "\(p.series) × \(p.reps) · " + (p.rpe.map { "RPE \($0)" } ?? "RIR \(p.rir)")
        let extra = [p.calentamiento.map { "Calentamiento: \(Programa.calentamiento($0))" }, p.tecnica.flatMap { $0.isEmpty ? nil : "Última serie: \($0)" }]
        e.nota = extra.compactMap { $0 }.joined(separator: "\n")
    }
    contexto.insert(e)
    e.sesion = sesion
    let previas = GymCalculos.anterior(de: nombre, en: historial, excepto: sesion).filter { $0.tipo != .calentamiento }
    let cuantas = max(plan?.series ?? (previas.isEmpty ? 3 : previas.count), 1)
    // Calentamiento primero (pirámide del programa sobre el peso de trabajo de la última vez), luego las series de trabajo.
    let calentamiento = Programa.seriesDeCalentamiento(plan?.calentamiento, pesoTrabajo: previas.first?.peso ?? 0)
    for (i, w) in calentamiento.enumerated() {
        let s = Serie(orden: i, peso: w.peso, reps: w.reps, tipo: .calentamiento)
        contexto.insert(s); s.ejercicio = e
    }
    let alFallo = plan?.tecnica?.hasPrefix("Failure") == true
    for i in 0..<cuantas {
        let ref = previas.indices.contains(i) ? previas[i] : previas.last
        let tipo: TipoSerie = i == cuantas - 1 && alFallo ? .fallo : (i < previas.count ? previas[i].tipo : .normal)
        let s = Serie(orden: calentamiento.count + i, peso: ref?.peso ?? 0, reps: ref?.reps ?? 0, tipo: tipo)
        contexto.insert(s); s.ejercicio = e
    }
}

/// Crea y guarda una sesión (vacía o desde una rutina) lista para entrenar.
func iniciarSesion(rutina: Rutina?, contexto: ModelContext, historial: [SesionGym], definiciones: [EjercicioDef]) -> SesionGym {
    let sesion = SesionGym(nombre: rutina?.nombre ?? "Entrenamiento")
    contexto.insert(sesion)
    for (i, nombre) in (rutina?.ejercicios ?? []).enumerated() {
        let grupo = definiciones.first { $0.nombre == nombre }?.grupo ?? ""
        agregarEjercicio(nombre: nombre, grupo: grupo, a: sesion, orden: i, contexto: contexto,
                         historial: historial, plan: rutina?.plan[nombre])
    }
    try? contexto.save()
    return sesion
}
