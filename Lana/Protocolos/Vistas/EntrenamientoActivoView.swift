import SwiftUI
import SwiftData

struct ResumenSesion: Identifiable {
    let id = UUID()
    let nombre: String
    let duracion: TimeInterval
    let volumen: Double
    let series: Int
    let records: [GymCalculos.Record]
    let grupos: [(String, Int)]
}

/// Pantalla de entrenamiento activo, como Hevy: series con check, anterior y descanso.
struct EntrenamientoActivoView: View {
    @Environment(\.modelContext) private var contexto
    @Environment(\.dismiss) private var cerrar
    @Bindable var sesion: SesionGym
    @Query(sort: \SesionGym.inicio, order: .reverse) private var historial: [SesionGym]

    @State private var descansoFin: Date?
    @State private var descansoTotal = 90
    @State private var agregando = false
    @State private var info: EjercicioLog?
    @State private var historialDe: NombreEjercicio?
    @State private var confirmandoCancelar = false
    @State private var resumen: ResumenSesion?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(sesion.ejerciciosOrdenados) { e in tarjeta(e) }

                    Button { agregando = true } label: {
                        Label("Agregar ejercicio", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                    }
                    Button("Cancelar entrenamiento", role: .destructive) { confirmandoCancelar = true }
                        .font(.subheadline).padding(.top, 8)
                }
                .padding(.horizontal)
                .padding(.bottom, 110)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(sesion.nombre)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { cerrar() } label: { Image(systemName: "chevron.down") }
                }
                ToolbarItem(placement: .principal) {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(cronometro(sesion.duracion)).font(.headline.monospacedDigit())
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Terminar", action: terminar).fontWeight(.bold)
                }
            }
            .safeAreaInset(edge: .bottom) { barraDescanso }
            .sheet(isPresented: $agregando) {
                SelectorEjercicioView { elegidos in
                    var orden = sesion.ejercicios?.count ?? 0
                    for d in elegidos {
                        agregarEjercicio(nombre: d.nombre, grupo: d.grupo, a: sesion, orden: orden,
                                         contexto: contexto, historial: historial)
                        orden += 1
                    }
                    try? contexto.save()
                }
            }
            .sheet(item: $info) { InfoEjercicioView(ejercicio: $0) }
            .sheet(item: $historialDe) { HistorialEjercicioSheet(nombre: $0.id) }
            .sheet(item: $resumen, onDismiss: { cerrar() }) { r in ResumenSesionView(resumen: r) }
            .confirmationDialog("¿Cancelar este entrenamiento?", isPresented: $confirmandoCancelar, titleVisibility: .visible) {
                Button("Borrar entrenamiento", role: .destructive) {
                    contexto.delete(sesion); try? contexto.save(); cerrar()
                }
            }
        }
    }

    // MARK: - Ejercicio

    private func tarjeta(_ e: EjercicioLog) -> some View {
        let previas = GymCalculos.anterior(de: e.nombre, en: historial, excepto: sesion)
        let marcas = GymCalculos.marcasPrevias(de: e.nombre, historial: historial, antesDe: sesion.inicio, excepto: sesion)
        let series = e.seriesOrdenadas
        let conRecord = series.filter { !GymCalculos.records(de: $0, en: e, previas: marcas).isEmpty }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                if e.grupoSuper != 0 {
                    Image(systemName: "link").font(.caption).foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(e.nombre).font(.headline).foregroundStyle(.green)
                            .onTapGesture { historialDe = NombreEjercicio(id: e.nombre) }
                        if conRecord > 0 {
                            Label("\(conRecord)", systemImage: "trophy.fill").font(.caption.weight(.bold)).foregroundStyle(.yellow)
                                .accessibilityLabel("\(conRecord) \(conRecord == 1 ? "récord" : "récords") en este ejercicio")
                        }
                    }
                    Text(e.objetivo.isEmpty ? "\(e.grupo) · descanso \(e.descansoSeg) s"
                         : "\(e.objetivo) · \(e.descansoSeg) s")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if Programa.catalogo[e.nombre] != nil {
                    Button { info = e } label: { Image(systemName: "play.rectangle").padding(8) }
                        .accessibilityLabel("Video y alternativas de \(e.nombre)")
                }
                Menu {
                    Menu("Descanso") {
                        ForEach([45, 60, 90, 120, 180], id: \.self) { s in
                            Button("\(s) s") { e.descansoSeg = s }
                        }
                    }
                    Button("Historial y récords", systemImage: "chart.line.uptrend.xyaxis") {
                        historialDe = NombreEjercicio(id: e.nombre)
                    }
                    Button(e.grupoSuper == 0 ? "Superserie con el siguiente" : "Quitar superserie",
                           systemImage: "link") { alternarSuperserie(e) }
                    Button("Quitar ejercicio", systemImage: "trash", role: .destructive) {
                        contexto.delete(e); try? contexto.save()
                    }
                } label: { Image(systemName: "ellipsis").padding(8) }
            }

            HStack {
                Text("SERIE").frame(width: 44)
                Text("ANTERIOR").frame(maxWidth: .infinity)
                Text("KG").frame(width: 64)
                Text("REPS").frame(width: 64)
                Image(systemName: "checkmark").frame(width: 36)
            }
            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)

            ForEach(series) { s in
                fila(s, en: e, previas: previas, marcas: marcas)
            }

            Button {
                let ultima = series.last { $0.tipo != .calentamiento } ?? series.last
                let nueva = Serie(orden: (series.last?.orden ?? -1) + 1, peso: ultima?.peso ?? 0, reps: ultima?.reps ?? 0)
                contexto.insert(nueva); nueva.ejercicio = e
                try? contexto.save()
            } label: {
                Label("Agregar serie", systemImage: "plus").font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func fila(_ serie: Serie, en e: EjercicioLog, previas: [Serie], marcas: MarcasEjercicio?) -> some View {
        @Bindable var s = serie
        let todas = e.seriesOrdenadas
        let trabajo = todas.filter { $0.tipo != .calentamiento }
        let calentamientos = todas.filter { $0.tipo == .calentamiento }
        let esCalentamiento = s.tipo == .calentamiento
        // Los calentamientos no cuentan: la serie 1 es la primera de trabajo.
        let idx = esCalentamiento ? (calentamientos.firstIndex { $0.id == s.id } ?? 0) : (trabajo.firstIndex { $0.id == s.id } ?? 0)
        let normales = todas.filter { $0.tipo == .normal }
        let numero = (normales.firstIndex { $0.id == s.id } ?? 0) + 1
        let previa = esCalentamiento ? nil : (previas.indices.contains(idx) ? previas[idx] : nil)
        let nombre = esCalentamiento ? "calentamiento \(idx + 1)" : "serie \(idx + 1)"
        let prs = GymCalculos.records(de: s, en: e, previas: marcas)
        return VStack(spacing: 2) {
            HStack {
                Menu {
                    ForEach(TipoSerie.allCases) { t in
                        Button(t.nombre) { s.tipo = t; try? contexto.save() }
                    }
                    Button("Borrar serie", role: .destructive) { contexto.delete(s); try? contexto.save() }
                } label: {
                    Text(s.tipo.letra ?? "\(numero)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(esCalentamiento ? .orange : (s.tipo == .normal ? .primary : .purple))
                        .frame(width: 44, height: 32)
                }
                .accessibilityLabel("Tipo de \(nombre)")
                Text(previa.map { "\(numeroLimpio($0.peso))×\($0.reps)" } ?? "—")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                CampoNumero(valor: $s.peso, etiqueta: "Peso en kilos, \(nombre)")
                    .padding(.vertical, 6).background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                CampoNumero(valor: Binding(get: { Double(s.reps) }, set: { s.reps = Int($0) }), etiqueta: "Repeticiones, \(nombre)")
                    .padding(.vertical, 6).background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                Button { alternar(s, en: e, marcas: marcas) } label: {
                    Image(systemName: s.hecha ? "checkmark.square.fill" : "square")
                        .font(.title2).foregroundStyle(s.hecha ? .green : .secondary).frame(width: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(s.hecha ? "\(nombre.prefix(1).uppercased() + nombre.dropFirst()) hecha" : "Marcar \(nombre)")
            }
            if !prs.isEmpty {
                Label("Récord: " + prs.map(\.corto).joined(separator: ", "), systemImage: "trophy.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.yellow)
                    .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 8)
                    .accessibilityLabel("Récord personal de \(prs.map(\.corto).joined(separator: ", "))")
            }
        }
        .padding(.vertical, 2)
        .background(s.hecha ? Color.green.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }

    private func alternar(_ s: Serie, en e: EjercicioLog, marcas: MarcasEjercicio?) {
        s.hecha.toggle()
        try? contexto.save()
        guard s.hecha else { return }
        if !GymCalculos.records(de: s, en: e, previas: marcas).isEmpty {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        // En superserie no hay descanso hasta cerrar la vuelta.
        let sigueEnSuper = e.grupoSuper != 0 &&
            sesion.ejerciciosOrdenados.contains { $0.grupoSuper == e.grupoSuper && $0.orden > e.orden }
        guard !sigueEnSuper else { return }
        descansoTotal = e.descansoSeg
        descansoFin = Date().addingTimeInterval(Double(e.descansoSeg))
        Recordatorios.avisarDescanso(en: e.descansoSeg)
    }

    private func alternarSuperserie(_ e: EjercicioLog) {
        let lista = sesion.ejerciciosOrdenados
        guard let i = lista.firstIndex(where: { $0.id == e.id }), i + 1 < lista.count else { return }
        let siguiente = lista[i + 1]
        if e.grupoSuper == 0 {
            let nuevo = (lista.map(\.grupoSuper).max() ?? 0) + 1
            e.grupoSuper = nuevo; siguiente.grupoSuper = nuevo
        } else {
            if siguiente.grupoSuper == e.grupoSuper { siguiente.grupoSuper = 0 }
            e.grupoSuper = 0
        }
        try? contexto.save()
    }

    // MARK: - Descanso

    @ViewBuilder
    private var barraDescanso: some View {
        if let fin = descansoFin {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let resta = max(0, Int(fin.timeIntervalSince(ctx.date).rounded(.up)))
                HStack(spacing: 12) {
                    Image(systemName: "timer")
                    Text(cronometro(Double(resta))).font(.title3.weight(.bold).monospacedDigit())
                    ProgressView(value: Double(descansoTotal - resta), total: Double(max(descansoTotal, 1)))
                    Button("−15") { descansoFin = fin.addingTimeInterval(-15) }
                    Button("+15") { descansoFin = fin.addingTimeInterval(15) }
                    Button("Saltar") { descansoFin = nil; Recordatorios.cancelarDescanso() }.fontWeight(.bold)
                }
                .font(.subheadline)
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
                .onChange(of: resta) { _, r in if r == 0 { descansoFin = nil } }
            }
        }
    }

    private func cronometro(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: - Terminar

    private func terminar() {
        // Sin una sola serie marcada no hay nada que guardar.
        if sesion.seriesHechas.isEmpty {
            contexto.delete(sesion); try? contexto.save()
            Recordatorios.cancelarDescanso()
            cerrar()
            return
        }
        // Como Hevy: lo que no marcaste no cuenta.
        for e in sesion.ejerciciosOrdenados {
            for s in e.seriesOrdenadas where !s.hecha { contexto.delete(s) }
            if e.seriesOrdenadas.allSatisfy({ !$0.hecha }) { contexto.delete(e) }
        }
        sesion.fin = Date()
        try? contexto.save()
        descansoFin = nil
        Recordatorios.cancelarDescanso()

        var porGrupo: [String: Int] = [:]
        for e in sesion.ejerciciosOrdenados {
            porGrupo[e.grupo, default: 0] += e.seriesOrdenadas.filter { $0.hecha && $0.tipo.cuentaVolumen }.count
        }
        resumen = ResumenSesion(
            nombre: sesion.nombre, duracion: sesion.duracion, volumen: sesion.volumen,
            series: sesion.seriesHechas.count,
            records: GymCalculos.records(de: sesion, historial: historial),
            grupos: porGrupo.filter { !$0.key.isEmpty }.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
        )
    }
}

struct ResumenSesionView: View {
    @Environment(\.dismiss) private var cerrar
    let resumen: ResumenSesion

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Duración", value: duracionTexto(resumen.duracion))
                    LabeledContent("Volumen", value: "\(numeroLimpio(resumen.volumen)) kg")
                    LabeledContent("Series", value: "\(resumen.series)")
                }
                if !resumen.records.isEmpty {
                    let ejercicios = resumen.records.reduce(into: [String]()) { if !$0.contains($1.ejercicio) { $0.append($1.ejercicio) } }
                    Section("🏆 \(ejercicios.count == 1 ? "1 ejercicio con récord" : "\(ejercicios.count) ejercicios con récord")") {
                        ForEach(ejercicios, id: \.self) { n in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(n).font(.subheadline.weight(.semibold))
                                ForEach(resumen.records.filter { $0.ejercicio == n }) { r in
                                    Label(r.detalle, systemImage: "trophy.fill").font(.caption)
                                        .foregroundStyle(.secondary).labelStyle(.titleAndIcon)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                if !resumen.grupos.isEmpty {
                    Section("Músculos trabajados (series)") {
                        ForEach(resumen.grupos, id: \.0) { g in LabeledContent(g.0, value: "\(g.1)") }
                    }
                }
            }
            .navigationTitle("¡Listo, \(resumen.nombre)!")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { cerrar() }.fontWeight(.bold) } }
        }
    }
}
