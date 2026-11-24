import SwiftUI
import SwiftData
import Charts

// MARK: - Selector de ejercicios

struct SelectorEjercicioView: View {
    @Environment(\.dismiss) private var cerrar
    @Environment(\.modelContext) private var contexto
    @Query(sort: \EjercicioDef.nombre) private var todos: [EjercicioDef]

    var alElegir: ([EjercicioDef]) -> Void

    @State private var busqueda = ""
    @State private var seleccion: Set<UUID> = []
    @State private var creando = false

    private var filtrados: [EjercicioDef] {
        busqueda.isEmpty ? todos : todos.filter { $0.nombre.localizedCaseInsensitiveContains(busqueda) }
    }
    private var grupos: [String] { Array(Set(filtrados.map(\.grupo))).sorted() }

    var body: some View {
        NavigationStack {
            List {
                ForEach(grupos, id: \.self) { g in
                    Section(g) {
                        ForEach(filtrados.filter { $0.grupo == g }) { d in
                            Button {
                                if seleccion.contains(d.id) { seleccion.remove(d.id) } else { seleccion.insert(d.id) }
                            } label: {
                                HStack {
                                    Text(d.nombre).foregroundStyle(.primary)
                                    Spacer()
                                    if seleccion.contains(d.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                if d.propio {
                                    Button(role: .destructive) { seleccion.remove(d.id); contexto.delete(d); try? contexto.save() } label: { Label("Borrar", systemImage: "trash") }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $busqueda, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar ejercicio")
            .navigationTitle("Ejercicios")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .topBarTrailing) { Button { creando = true } label: { Image(systemName: "plus") } }
            }
            .safeAreaInset(edge: .bottom) {
                if !seleccion.isEmpty {
                    Button {
                        alElegir(todos.filter { seleccion.contains($0.id) })
                        cerrar()
                    } label: {
                        Text("Agregar (\(seleccion.count))").font(.headline)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color.green, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal).padding(.bottom, 8)
                }
            }
            .sheet(isPresented: $creando) { NuevoEjercicioView() }
        }
    }
}

struct NuevoEjercicioView: View {
    @Environment(\.dismiss) private var cerrar
    @Environment(\.modelContext) private var contexto
    @State private var nombre = ""
    @State private var grupo = "Pecho"
    static let grupos = ["Pecho", "Espalda", "Hombro", "Bíceps", "Tríceps", "Cuádriceps", "Isquios",
                         "Glúteo", "Pantorrilla", "Core", "Otro"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre", text: $nombre)
                Picker("Grupo muscular", selection: $grupo) {
                    ForEach(Self.grupos, id: \.self) { Text($0) }
                }
            }
            .navigationTitle("Ejercicio nuevo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        contexto.insert(EjercicioDef(nombre: nombre.trimmingCharacters(in: .whitespaces), grupo: grupo, propio: true))
                        try? contexto.save(); cerrar()
                    }
                    .disabled(nombre.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Editor de rutina

struct EditorRutinaView: View {
    @Environment(\.dismiss) private var cerrar
    @Environment(\.modelContext) private var contexto
    @Query private var rutinas: [Rutina]

    var rutina: Rutina?
    @State private var nombre = ""
    @State private var ejercicios: [String] = []
    @State private var agregando = false
    @State private var cargado = false

    var body: some View {
        NavigationStack {
            List {
                Section { TextField("Nombre de la rutina", text: $nombre) }
                Section("Ejercicios") {
                    ForEach(ejercicios, id: \.self) { Text($0) }
                        .onDelete { ejercicios.remove(atOffsets: $0) }
                        .onMove { ejercicios.move(fromOffsets: $0, toOffset: $1) }
                    Button { agregando = true } label: { Label("Agregar ejercicio", systemImage: "plus.circle") }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(rutina == nil ? "Nueva rutina" : "Editar rutina")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: guardar).fontWeight(.bold)
                        .disabled(nombre.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $agregando) {
                SelectorEjercicioView { ejercicios.append(contentsOf: $0.map(\.nombre).filter { !ejercicios.contains($0) }) }
            }
            .onAppear {
                guard !cargado else { return }
                cargado = true
                nombre = rutina?.nombre ?? ""
                ejercicios = rutina?.ejercicios ?? []
            }
        }
    }

    private func guardar() {
        let n = nombre.trimmingCharacters(in: .whitespaces)
        if let r = rutina {
            r.nombre = n; r.ejercicios = ejercicios
        } else {
            contexto.insert(Rutina(nombre: n, ejercicios: ejercicios, orden: rutinas.count))
        }
        try? contexto.save(); cerrar()
    }
}

// MARK: - Detalle de una sesión pasada

struct DetalleSesionView: View {
    @Environment(\.modelContext) private var contexto
    @Environment(\.dismiss) private var cerrar
    @Query private var rutinas: [Rutina]
    @Query private var todas: [SesionGym]
    let sesion: SesionGym
    @State private var confirmando = false

    var body: some View {
        List {
            Section {
                LabeledContent("Fecha", value: sesion.inicio.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Duración", value: duracionTexto(sesion.duracion))
                LabeledContent("Volumen", value: "\(numeroLimpio(sesion.volumen)) kg")
            }
            ForEach(sesion.ejerciciosOrdenados) { e in
                let previas = GymCalculos.marcasPrevias(de: e.nombre, historial: todas, antesDe: sesion.inicio, excepto: sesion)
                let trabajo = e.seriesOrdenadas.filter { $0.tipo != .calentamiento }
                Section(e.nombre) {
                    ForEach(e.seriesOrdenadas) { s in
                        let prs = GymCalculos.records(de: s, en: e, previas: previas)
                        HStack {
                            Text(s.tipo.letra ?? "\((trabajo.firstIndex { $0.id == s.id } ?? 0) + 1)")
                                .fontWeight(.bold).frame(width: 30, alignment: .leading)
                            Text("\(numeroLimpio(s.peso)) kg × \(s.reps)")
                            if !prs.isEmpty {
                                Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                                    .accessibilityLabel("Récord de \(prs.map(\.corto).joined(separator: ", "))")
                            }
                            Spacer()
                            if s.tipo.cuentaVolumen && s.reps > 0 {
                                Text("1RM \(numeroLimpio(GymCalculos.e1RM(peso: s.peso, reps: s.reps)))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    NavigationLink { HistorialEjercicioView(nombre: e.nombre) } label: {
                        Label("Historial y récords", systemImage: "chart.line.uptrend.xyaxis").font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle(sesion.nombre)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Guardar como rutina", systemImage: "square.and.arrow.down") {
                        contexto.insert(Rutina(nombre: sesion.nombre, ejercicios: sesion.ejerciciosOrdenados.map(\.nombre),
                                               orden: rutinas.count))
                        try? contexto.save()
                    }
                    Button("Borrar", systemImage: "trash", role: .destructive) { confirmando = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .confirmationDialog("¿Borrar este entrenamiento?", isPresented: $confirmando, titleVisibility: .visible) {
            Button("Borrar", role: .destructive) { contexto.delete(sesion); try? contexto.save(); cerrar() }
        }
    }
}

// MARK: - Historial de un ejercicio

struct NombreEjercicio: Identifiable { let id: String }

/// Sheet con barra propia para abrir el historial desde el entrenamiento activo.
struct HistorialEjercicioSheet: View {
    @Environment(\.dismiss) private var cerrar
    let nombre: String
    var body: some View {
        NavigationStack {
            HistorialEjercicioView(nombre: nombre)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() }.fontWeight(.bold) } }
        }
    }
}

/// Récords, gráfica y todas las sesiones de un ejercicio.
struct HistorialEjercicioView: View {
    @Query(sort: \SesionGym.inicio) private var sesiones: [SesionGym]
    let nombre: String

    private struct Entrada: Identifiable {
        let sesion: SesionGym
        let ejercicio: EjercicioLog
        var id: UUID { sesion.id }
    }

    private var entradas: [Entrada] {
        sesiones.filter { $0.fin != nil }.compactMap { s in
            guard let e = s.ejerciciosOrdenados.first(where: { $0.nombre == nombre }),
                  !GymCalculos.validas(e).isEmpty else { return nil }
            return Entrada(sesion: s, ejercicio: e)
        }
    }

    private struct Punto: Identifiable { let id = UUID(); let fecha: Date; let serie: String; let valor: Double }

    private var puntos: [Punto] {
        entradas.flatMap { en in
            [Punto(fecha: en.sesion.inicio, serie: "1RM estimado", valor: GymCalculos.mejor1RM(en.ejercicio)),
             Punto(fecha: en.sesion.inicio, serie: "Peso máximo", valor: GymCalculos.mejorPeso(en.ejercicio))]
        }
    }

    /// Mejor valor de cada marca y la fecha en que se logró (el primero que la alcanzó).
    private var marcas: [(String, String, Date)] {
        var peso: (Double, Date)?, rm: (Double, Date)?, vol: (Double, Serie, Date)?, reps: (Int, Serie, Date)?
        for en in entradas {
            for x in GymCalculos.validas(en.ejercicio) {
                let f = en.sesion.inicio
                if x.peso > (peso?.0 ?? 0) { peso = (x.peso, f) }
                let r = GymCalculos.e1RM(peso: x.peso, reps: x.reps)
                if r > (rm?.0 ?? 0) + 0.001 { rm = (r, f) }
                if x.peso * Double(x.reps) > (vol?.0 ?? 0) + 0.001 { vol = (x.peso * Double(x.reps), x, f) }
                if x.reps > (reps?.0 ?? 0) { reps = (x.reps, x, f) }
            }
        }
        var l: [(String, String, Date)] = []
        if let p = peso { l.append(("Peso máximo", kg(p.0), p.1)) }
        if let r = rm { l.append(("1RM estimado", kg(r.0), r.1)) }
        if let v = vol { l.append(("Mejor serie (volumen)", "\(numeroLimpio(v.1.peso)) kg × \(v.1.reps)", v.2)) }
        if let r = reps { l.append(("Más repeticiones", "\(r.0) con \(numeroLimpio(r.1.peso)) kg", r.2)) }
        return l
    }

    var body: some View {
        List {
            if entradas.isEmpty {
                Text("Aún no hay series terminadas de este ejercicio.").foregroundStyle(.secondary)
            } else {
                Section("🏆 Récords personales") {
                    ForEach(marcas, id: \.0) { m in
                        LabeledContent {
                            Text(m.1).fontWeight(.semibold)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(m.0)
                                Text(m.2.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Section("Progreso") {
                    Chart(puntos) { p in
                        LineMark(x: .value("Fecha", p.fecha), y: .value("kg", p.valor))
                            .foregroundStyle(by: .value("Serie", p.serie))
                        PointMark(x: .value("Fecha", p.fecha), y: .value("kg", p.valor))
                            .foregroundStyle(by: .value("Serie", p.serie))
                    }
                    .chartForegroundStyleScale(["1RM estimado": Color.green, "Peso máximo": Color.orange])
                    .chartLegend(position: .bottom)
                    .frame(height: 210)
                    .accessibilityLabel("Gráfica de 1RM estimado y peso máximo por sesión")
                    LabeledContent("Sesiones", value: "\(entradas.count)")
                }
                ForEach(entradas.reversed()) { en in
                    let prs = GymCalculos.records(de: en.sesion, historial: sesiones).filter { $0.ejercicio == nombre }
                    let trabajo = en.ejercicio.seriesOrdenadas.filter { $0.tipo != .calentamiento }
                    Section {
                        ForEach(en.ejercicio.seriesOrdenadas) { s in
                            HStack {
                                Text(s.tipo.letra ?? "\((trabajo.firstIndex { $0.id == s.id } ?? 0) + 1)")
                                    .fontWeight(.bold).frame(width: 30, alignment: .leading)
                                    .foregroundStyle(s.tipo == .calentamiento ? .orange : .primary)
                                Text("\(numeroLimpio(s.peso)) kg × \(s.reps)")
                                Spacer()
                                if s.tipo.cuentaVolumen && s.reps > 0 {
                                    Text("1RM \(numeroLimpio(GymCalculos.e1RM(peso: s.peso, reps: s.reps)))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text(en.sesion.inicio.formatted(date: .abbreviated, time: .omitted))
                            if !prs.isEmpty {
                                Label(prs.map { $0.tipo.corto }.joined(separator: ", "), systemImage: "trophy.fill")
                                    .foregroundStyle(.yellow).textCase(nil)
                            }
                            Spacer()
                            Text(en.sesion.nombre).textCase(nil)
                        }
                    }
                }
            }
        }
        .navigationTitle(nombre)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Progreso

struct ProgresoView: View {
    @Query(sort: \SesionGym.inicio, order: .reverse) private var sesiones: [SesionGym]
    @State private var busqueda = ""

    private var terminadas: [SesionGym] { sesiones.filter { $0.fin != nil } }

    private struct Fila: Identifiable { let id: String; let veces: Int; let mejor1RM: Double; let ultimo: Date }

    /// Cada ejercicio que has hecho, el más reciente primero.
    private var filas: [Fila] {
        var d: [String: Fila] = [:]
        for s in terminadas {   // ya viene del más reciente al más viejo
            for e in s.ejerciciosOrdenados where !GymCalculos.validas(e).isEmpty {
                let prev = d[e.nombre]
                d[e.nombre] = Fila(id: e.nombre, veces: (prev?.veces ?? 0) + 1,
                                   mejor1RM: max(prev?.mejor1RM ?? 0, GymCalculos.mejor1RM(e)), ultimo: prev?.ultimo ?? s.inicio)
            }
        }
        let todas = d.values.sorted { $0.ultimo > $1.ultimo }
        return busqueda.isEmpty ? todas : todas.filter { $0.id.localizedCaseInsensitiveContains(busqueda) }
    }

    /// Series por grupo muscular en los últimos 30 días.
    private var porGrupo: [(String, Int)] {
        let desde = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        var d: [String: Int] = [:]
        for s in terminadas where s.inicio >= desde {
            for e in s.ejerciciosOrdenados where !e.grupo.isEmpty {
                d[e.grupo, default: 0] += e.seriesOrdenadas.filter { $0.hecha && $0.tipo.cuentaVolumen }.count
            }
        }
        return d.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    var body: some View {
        List {
            if terminadas.isEmpty {
                Text("Termina tu primer entrenamiento para ver tu progreso.").foregroundStyle(.secondary)
            } else {
                Section("Ejercicios · toca uno para ver su historial") {
                    ForEach(filas) { f in
                        NavigationLink { HistorialEjercicioView(nombre: f.id) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.id).font(.subheadline.weight(.semibold))
                                    Text("\(f.veces) \(f.veces == 1 ? "sesión" : "sesiones") · último \(f.ultimo.formatted(.dateTime.day().month(.abbreviated)))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("1RM \(numeroLimpio(f.mejor1RM))").font(.caption.monospacedDigit()).foregroundStyle(.green)
                            }
                        }
                    }
                }
                if busqueda.isEmpty {
                    Section("Series por músculo · 30 días") {
                        Chart(porGrupo, id: \.0) { g in
                            BarMark(x: .value("Series", g.1), y: .value("Músculo", g.0)).foregroundStyle(.green)
                        }
                        .frame(height: CGFloat(max(porGrupo.count, 1)) * 30 + 20)
                    }
                }
            }
        }
        .searchable(text: $busqueda, prompt: "Buscar ejercicio")
        .navigationTitle("Progreso")
    }
}
