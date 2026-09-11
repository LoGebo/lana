import SwiftUI
import SwiftData
import WidgetKit

/// Captura rápida: teclado grande, categoría de un tap y listo.
struct EditorMovimientoView: View {
    @Environment(\.modelContext) private var contexto
    @Environment(\.dismiss) private var cerrar

    @Query(sort: \Categoria.orden) private var categorias: [Categoria]
    @Query(sort: \Cuenta.orden) private var cuentas: [Cuenta]

    /// Si viene lleno, estamos editando en vez de crear.
    var movimiento: Movimiento?
    /// Categoría preseleccionada cuando entras desde el registro rápido.
    var categoriaInicial: Categoria?

    @State private var centavos = ""
    @State private var tipo: TipoMovimiento = .gasto
    @State private var categoriaSel: Categoria?
    @State private var cuentaSel: Cuenta?
    @State private var cuentaDestino: Cuenta?
    @State private var comercio = ""
    @State private var nota = ""
    @State private var fecha = Date()
    @State private var mostrandoDetalles = false
    @State private var cargado = false

    /// Qué campo de texto trae el foco. Mientras haya uno, escondemos el
    /// teclado numérico: si no, le picas creyendo que escribes y le sumas al monto.
    @FocusState private var campoActivo: CampoDeTexto?

    private enum CampoDeTexto: Hashable { case comercio, nota }


    private var monto: Double { (Double(centavos) ?? 0) / 100 }

    private var categoriasVisibles: [Categoria] {
        categorias.filter { $0.esIngreso == (tipo == .ingreso) }
    }

    private var cuentasActivas: [Cuenta] { cuentas.filter(\.activa) }

    private var puedeGuardar: Bool {
        guard monto > 0, cuentaSel != nil else { return false }
        if tipo == .transferencia { return cuentaDestino != nil && cuentaDestino?.id != cuentaSel?.id }
        return true
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                selectorTipo
                montoGrande

                ScrollView {
                    VStack(spacing: 18) {
                        if tipo == .transferencia {
                            seccionCuentas(titulo: "De", seleccion: $cuentaSel)
                            seccionCuentas(titulo: "A", seleccion: $cuentaDestino)
                        } else {
                            seccionCategorias
                            seccionCuentas(titulo: "Cuenta", seleccion: $cuentaSel)
                        }
                        seccionDetalles
                    }
                    .padding(.vertical, 12)
                }
                .scrollDismissesKeyboard(.interactively)

                if campoActivo == nil {
                    tecladoNumerico
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(movimiento == nil ? "Nuevo movimiento" : "Editar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { cerrar() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: guardar)
                        .fontWeight(.semibold)
                        .disabled(!puedeGuardar)
                }
            }
            .animation(.snappy(duration: 0.22), value: campoActivo)
            .toolbar {
                if campoActivo != nil {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Listo") { campoActivo = nil }
                            .fontWeight(.semibold)
                    }
                }
            }
            .onAppear(perform: cargarInicial)
        }
    }

    // MARK: - Piezas

    private var selectorTipo: some View {
        Picker("Tipo", selection: $tipo) {
            ForEach(TipoMovimiento.allCases) { t in
                Text(t.nombre).tag(t)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.top, 8)
        .onChange(of: tipo) { _, nuevo in
            if categoriaSel?.esIngreso != (nuevo == .ingreso) { categoriaSel = nil }
        }
    }

    private var montoGrande: some View {
        VStack(spacing: 2) {
            Text(pesos(monto))
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundStyle(monto == 0 ? Color.secondary : colorTipo)
                .contentTransition(.numericText())
                .animation(.snappy, value: centavos)
            if let c = categoriaSel {
                Text("\(c.emoji) \(c.nombre)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture { campoActivo = nil }
    }

    private var colorTipo: Color {
        switch tipo {
        case .gasto: .primary
        case .ingreso: .green
        case .transferencia: .blue
        }
    }

    private var seccionCategorias: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Categoría")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: [GridItem(.fixed(38)), GridItem(.fixed(38))], spacing: 8) {
                    ForEach(categoriasVisibles) { c in
                        Button {
                            categoriaSel = (categoriaSel?.id == c.id) ? nil : c
                        } label: {
                            HStack(spacing: 5) {
                                Text(c.emoji)
                                Text(c.nombre).font(.subheadline)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(
                                    categoriaSel?.id == c.id
                                    ? Color(hex: c.colorHex).opacity(0.9)
                                    : Color(.secondarySystemGroupedBackground)
                                )
                            )
                            .foregroundStyle(categoriaSel?.id == c.id ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func seccionCuentas(titulo: String, seleccion: Binding<Cuenta?>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titulo)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(cuentasActivas) { c in
                        Button {
                            seleccion.wrappedValue = c
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: c.tipo.icono).font(.caption)
                                Text(c.nombre).font(.subheadline)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(
                                    seleccion.wrappedValue?.id == c.id
                                    ? Color(hex: c.colorHex).opacity(0.9)
                                    : Color(.secondarySystemGroupedBackground)
                                )
                            )
                            .foregroundStyle(seleccion.wrappedValue?.id == c.id ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var seccionDetalles: some View {
        VStack(spacing: 10) {
            DisclosureGroup("Detalles", isExpanded: $mostrandoDetalles) {
                VStack(spacing: 12) {
                    TextField("¿Dónde? (7-Eleven, Uber, gym…)", text: $comercio)
                        .textInputAutocapitalization(.words)
                        .focused($campoActivo, equals: .comercio)
                        .submitLabel(.done)
                        .onSubmit { campoActivo = nil }
                        .onChange(of: comercio) { _, nuevo in
                            // Si aún no eliges categoría, la deducimos del comercio.
                            guard categoriaSel == nil, tipo == .gasto else { return }
                            if let adivinada = Adivinador.buscar(nuevo, en: categoriasVisibles) {
                                withAnimation(.snappy) { categoriaSel = adivinada }
                            }
                        }
                    Divider()
                    DatePicker("Fecha", selection: $fecha, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.locale, Locale(identifier: "es_MX"))
                    Divider()
                    TextField("Nota", text: $nota, axis: .vertical)
                        .focused($campoActivo, equals: .nota)
                }
                .padding(.top, 8)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
        }
    }

    private var tecladoNumerico: some View {
        let teclas = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "00", "0", "⌫"]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(teclas, id: \.self) { t in
                Button {
                    tocarTecla(t)
                } label: {
                    Text(t)
                        .font(.title2.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    // MARK: - Acciones

    private func tocarTecla(_ tecla: String) {
        switch tecla {
        case "⌫":
            if !centavos.isEmpty { centavos.removeLast() }
        default:
            guard centavos.count + tecla.count <= 9 else { return }
            if centavos.isEmpty && tecla == "00" { return }
            centavos += tecla
        }
    }

    private func cargarInicial() {
        guard !cargado else { return }
        cargado = true

        if let m = movimiento {
            centavos = String(Int((m.monto * 100).rounded()))
            tipo = m.tipo
            categoriaSel = m.categoria
            cuentaSel = m.cuenta
            cuentaDestino = cuentas.first { $0.id == m.cuentaDestinoID }
            comercio = m.comercio
            nota = m.nota
            fecha = m.fecha
        } else {
            if let inicial = categoriaInicial { categoriaSel = inicial }
            cuentaSel = Preferencias.cuentaInicial(entre: cuentas)
        }
    }

    private func guardar() {
        guard puedeGuardar else { return }

        let destino = tipo == .transferencia ? cuentaDestino?.id : nil
        let cat = tipo == .transferencia ? nil : categoriaSel

        if let m = movimiento {
            m.monto = monto
            m.tipo = tipo
            m.categoria = cat
            m.cuenta = cuentaSel
            m.cuentaDestinoID = destino
            m.comercio = comercio.trimmingCharacters(in: .whitespaces)
            m.nota = nota
            m.fecha = fecha
            m.creadoPorAtajo = false
        } else {
            let nuevo = Movimiento(
                monto: monto,
                fecha: fecha,
                tipo: tipo,
                comercio: comercio.trimmingCharacters(in: .whitespaces),
                nota: nota,
                cuenta: cuentaSel,
                categoria: cat,
                cuentaDestinoID: destino
            )
            contexto.insert(nuevo)
        }

        Preferencias.ultimaCuenta = cuentaSel?.id
        try? contexto.save()
        WidgetCenter.shared.reloadAllTimelines()
        cerrar()
    }
}
