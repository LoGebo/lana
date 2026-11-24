import SwiftUI
import SwiftData

// MARK: - Agregar alimento

struct AgregarAlimentoView: View {
    @Environment(\.dismiss) private var cerrar
    @Environment(\.modelContext) private var contexto
    @Query(sort: \Alimento.nombre) private var alimentos: [Alimento]

    let tiempo: TiempoComida
    let dia: Date

    @State private var busqueda = ""
    @State private var creando = false
    @State private var rapido = false
    @State private var elegido: Alimento?

    private var filtrados: [Alimento] {
        busqueda.isEmpty ? alimentos : alimentos.filter { $0.nombre.localizedCaseInsensitiveContains(busqueda) }
    }
    private var recientes: [Alimento] {
        alimentos.filter { $0.ultimoUso != nil }.sorted { $0.ultimoUso! > $1.ultimoUso! }.prefix(8).map { $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                if busqueda.isEmpty {
                    if !recientes.isEmpty { Section("Recientes") { ForEach(recientes) { fila($0) } } }
                    let favs = alimentos.filter(\.favorito)
                    if !favs.isEmpty { Section("Favoritos") { ForEach(favs) { fila($0) } } }
                }
                Section(busqueda.isEmpty ? "Todos" : "Resultados") {
                    ForEach(filtrados) { fila($0) }
                }
            }
            .searchable(text: $busqueda, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar alimento")
            .navigationTitle(tiempo.nombre)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { cerrar() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Añadir rápido (solo macros)", systemImage: "bolt.fill") { rapido = true }
                        Button("Crear alimento", systemImage: "plus") { creando = true }
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $elegido) { a in
                DetalleAlimentoView(alimento: a, tiempo: tiempo, dia: dia) { cerrar() }
            }
            .sheet(isPresented: $creando) { EditorAlimentoView(alimento: nil) }
            .sheet(isPresented: $rapido) { AnadirRapidoView(tiempo: tiempo, dia: dia) { cerrar() } }
        }
    }

    private func fila(_ a: Alimento) -> some View {
        Button { elegido = a } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.nombre).foregroundStyle(.primary)
                    Text("\(a.porcion) · P \(numeroLimpio(a.proteina)) C \(numeroLimpio(a.carbs)) G \(numeroLimpio(a.grasa))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(a.kcal))").foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
            Button { a.favorito.toggle(); try? contexto.save() } label: { Image(systemName: "star") }.tint(.yellow)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { contexto.delete(a); try? contexto.save() } label: { Image(systemName: "trash") }
        }
    }
}

struct DetalleAlimentoView: View {
    @Environment(\.dismiss) private var cerrar
    @Environment(\.modelContext) private var contexto
    let alimento: Alimento
    let tiempo: TiempoComida
    let dia: Date
    var alAgregar: () -> Void

    @State private var porciones: Double = 1
    @State private var editando = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(alimento.nombre).font(.headline)
                    Stepper(value: $porciones, in: 0.25...50, step: 0.25) {
                        Text("\(numeroLimpio(porciones)) × \(alimento.porcion)")
                    }
                }
                Section("Total") {
                    LabeledContent("Calorías", value: "\(Int((alimento.kcal * porciones).rounded()))")
                    LabeledContent("Proteína", value: "\(numeroLimpio((alimento.proteina * porciones * 10).rounded() / 10)) g")
                    LabeledContent("Carbohidratos", value: "\(numeroLimpio((alimento.carbs * porciones * 10).rounded() / 10)) g")
                    LabeledContent("Grasa", value: "\(numeroLimpio((alimento.grasa * porciones * 10).rounded() / 10)) g")
                }
                Section { Button("Editar alimento") { editando = true } }
            }
            .navigationTitle("Añadir a \(tiempo.nombre)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Atrás") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Añadir") {
                        contexto.insert(ComidaLog(dia: dia, tiempo: tiempo, nombre: alimento.nombre, porcionTexto: alimento.porcion,
                                                  porciones: porciones, kcal: alimento.kcal, proteina: alimento.proteina,
                                                  carbs: alimento.carbs, grasa: alimento.grasa))
                        alimento.ultimoUso = Date()
                        try? contexto.save()
                        cerrar(); alAgregar()
                    }
                    .fontWeight(.bold)
                }
            }
            .sheet(isPresented: $editando) { EditorAlimentoView(alimento: alimento) }
        }
    }
}

struct EditorAlimentoView: View {
    @Environment(\.dismiss) private var cerrar
    @Environment(\.modelContext) private var contexto
    var alimento: Alimento?

    @State private var nombre = ""
    @State private var porcion = "100 g"
    @State private var kcal = 0.0
    @State private var proteina = 0.0
    @State private var carbs = 0.0
    @State private var grasa = 0.0
    @State private var cargado = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre", text: $nombre)
                    TextField("Porción (ej. 100 g, 1 pieza)", text: $porcion)
                }
                Section("Por porción") {
                    fila("Calorías", $kcal, "kcal")
                    fila("Proteína", $proteina, "g")
                    fila("Carbohidratos", $carbs, "g")
                    fila("Grasa", $grasa, "g")
                }
            }
            .navigationTitle(alimento == nil ? "Alimento nuevo" : "Editar alimento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: guardar).fontWeight(.bold)
                        .disabled(nombre.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard !cargado, let a = alimento else { return }
                cargado = true
                nombre = a.nombre; porcion = a.porcion; kcal = a.kcal; proteina = a.proteina; carbs = a.carbs; grasa = a.grasa
            }
        }
    }

    private func fila(_ t: String, _ v: Binding<Double>, _ u: String) -> some View {
        HStack { Text(t); Spacer(); CampoNumero(valor: v, ancho: 80, alineacion: .trailing); Text(u).foregroundStyle(.secondary) }
    }

    private func guardar() {
        let n = nombre.trimmingCharacters(in: .whitespaces)
        if let a = alimento {
            a.nombre = n; a.porcion = porcion; a.kcal = kcal; a.proteina = proteina; a.carbs = carbs; a.grasa = grasa
        } else {
            contexto.insert(Alimento(nombre: n, porcion: porcion, kcal: kcal, proteina: proteina, carbs: carbs, grasa: grasa))
        }
        try? contexto.save(); cerrar()
    }
}

struct AnadirRapidoView: View {
    @Environment(\.dismiss) private var cerrar
    @Environment(\.modelContext) private var contexto
    let tiempo: TiempoComida
    let dia: Date
    var alAgregar: () -> Void

    @State private var nombre = ""
    @State private var kcal = 0.0
    @State private var proteina = 0.0
    @State private var carbs = 0.0
    @State private var grasa = 0.0

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre (opcional)", text: $nombre)
                HStack { Text("Calorías"); Spacer(); CampoNumero(valor: $kcal, ancho: 80, alineacion: .trailing) }
                HStack { Text("Proteína (g)"); Spacer(); CampoNumero(valor: $proteina, ancho: 80, alineacion: .trailing) }
                HStack { Text("Carbohidratos (g)"); Spacer(); CampoNumero(valor: $carbs, ancho: 80, alineacion: .trailing) }
                HStack { Text("Grasa (g)"); Spacer(); CampoNumero(valor: $grasa, ancho: 80, alineacion: .trailing) }
            }
            .navigationTitle("Añadir rápido")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Añadir") {
                        // Si solo pusiste macros, calculamos las calorías (4/4/9).
                        let k = kcal > 0 ? kcal : proteina * 4 + carbs * 4 + grasa * 9
                        contexto.insert(ComidaLog(dia: dia, tiempo: tiempo, nombre: nombre.isEmpty ? "Añadido rápido" : nombre,
                                                  porcionTexto: "1 porción", porciones: 1, kcal: k,
                                                  proteina: proteina, carbs: carbs, grasa: grasa))
                        try? contexto.save(); cerrar(); alAgregar()
                    }
                    .fontWeight(.bold).disabled(kcal + proteina + carbs + grasa == 0)
                }
            }
        }
    }
}

struct EditarPorcionesView: View {
    @Environment(\.dismiss) private var cerrar
    @Environment(\.modelContext) private var contexto
    @Bindable var log: ComidaLog

    var body: some View {
        NavigationStack {
            Form {
                Section(log.nombre) {
                    Stepper(value: $log.porciones, in: 0.25...50, step: 0.25) {
                        Text("\(numeroLimpio(log.porciones)) × \(log.porcionTexto)")
                    }
                    Picker("Comida", selection: Binding(get: { log.tiempo }, set: { log.tiempo = $0 })) {
                        ForEach(TiempoComida.allCases) { Text($0.nombre).tag($0) }
                    }
                }
                Section("Total") {
                    LabeledContent("Calorías", value: "\(Int(log.kcalTotal.rounded()))")
                    LabeledContent("Proteína", value: "\(numeroLimpio((log.proteinaTotal * 10).rounded() / 10)) g")
                    LabeledContent("Carbohidratos", value: "\(numeroLimpio((log.carbsTotal * 10).rounded() / 10)) g")
                    LabeledContent("Grasa", value: "\(numeroLimpio((log.grasaTotal * 10).rounded() / 10)) g")
                }
            }
            .navigationTitle("Editar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { try? contexto.save(); cerrar() }.fontWeight(.bold) }
            }
        }
    }
}

// MARK: - Metas

struct MetasView: View {
    @Environment(\.dismiss) private var cerrar
    @AppStorage(LlavesMetas.kcal) private var kcal: Double = 0
    @AppStorage(LlavesMetas.proteina) private var proteina: Double = 0
    @AppStorage(LlavesMetas.carbs) private var carbs: Double = 0
    @AppStorage(LlavesMetas.grasa) private var grasa: Double = 0
    @AppStorage(LlavesMetas.agua) private var agua: Double = 3000

    @AppStorage("protocolos.perfil.peso") private var peso: Double = 0
    @AppStorage("protocolos.perfil.estatura") private var estatura: Double = 0
    @AppStorage("protocolos.perfil.edad") private var edad: Double = 0
    @AppStorage("protocolos.perfil.hombre") private var hombre = true
    @AppStorage("protocolos.perfil.actividad") private var actividad = 1.5

    private var listo: Bool { peso > 0 && estatura > 0 && edad > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tus datos") {
                    HStack { Text("Peso (kg)"); Spacer(); CampoNumero(valor: $peso, ancho: 80, alineacion: .trailing) }
                    HStack { Text("Estatura (cm)"); Spacer(); CampoNumero(valor: $estatura, ancho: 80, alineacion: .trailing) }
                    HStack { Text("Edad"); Spacer(); CampoNumero(valor: $edad, ancho: 80, alineacion: .trailing) }
                    Picker("Sexo", selection: $hombre) { Text("Hombre").tag(true); Text("Mujer").tag(false) }
                    Picker("Actividad", selection: $actividad) {
                        Text("Ligera (oficina + gym 3-4 días)").tag(1.4)
                        Text("Moderada (activo + gym 4 días)").tag(1.5)
                        Text("Alta (trabajo físico + gym)").tag(1.6)
                    }
                }
                Section {
                    Button("Calcular para ganar músculo") { calcular() }.disabled(!listo)
                } footer: {
                    Text("Mifflin-St Jeor × actividad, +300 kcal. Proteína 2.0 g/kg, grasa 1.0 g/kg y el resto en carbohidratos. Es un punto de partida: pésate en ayunas y ajusta cada 2 semanas según cómo cambie tu peso (meta ~0.25-0.4% del peso por semana).")
                }
                Section("Metas diarias (editables)") {
                    HStack { Text("Calorías"); Spacer(); CampoNumero(valor: $kcal, ancho: 80, alineacion: .trailing) }
                    HStack { Text("Proteína (g)"); Spacer(); CampoNumero(valor: $proteina, ancho: 80, alineacion: .trailing) }
                    HStack { Text("Carbohidratos (g)"); Spacer(); CampoNumero(valor: $carbs, ancho: 80, alineacion: .trailing) }
                    HStack { Text("Grasa (g)"); Spacer(); CampoNumero(valor: $grasa, ancho: 80, alineacion: .trailing) }
                    HStack { Text("Agua (ml)"); Spacer(); CampoNumero(valor: $agua, ancho: 80, alineacion: .trailing) }
                }
            }
            .navigationTitle("Metas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() }.fontWeight(.bold) } }
        }
    }

    private func calcular() {
        let bmr = 10 * peso + 6.25 * estatura - 5 * edad + (hombre ? 5 : -161)
        let total = bmr * actividad + 300
        kcal = total.rounded()
        proteina = (peso * 2.0).rounded()
        grasa = (peso * 1.0).rounded()
        agua = (peso * 37.5 / 50).rounded() * 50   // 35-40 ml/kg
        carbs = max(0, ((total - proteina * 4 - grasa * 9) / 4).rounded())
    }
}
