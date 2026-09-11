import SwiftUI
import SwiftData

struct MovimientosView: View {
    @Environment(\.modelContext) private var contexto
    @Query(sort: \Movimiento.fecha, order: .reverse) private var movimientos: [Movimiento]
    @Query(sort: \Categoria.orden) private var categorias: [Categoria]
    @Query(sort: \Cuenta.orden) private var cuentas: [Cuenta]

    @Binding var mostrandoCaptura: Bool

    @State private var busqueda = ""
    @State private var filtroCategoria: Categoria?
    @State private var filtroCuenta: Cuenta?
    @State private var editando: Movimiento?

    private var filtrados: [Movimiento] {
        movimientos.filter { m in
            let coincideTexto = busqueda.isEmpty
                || m.comercio.localizedCaseInsensitiveContains(busqueda)
                || m.nota.localizedCaseInsensitiveContains(busqueda)
                || (m.categoria?.nombre.localizedCaseInsensitiveContains(busqueda) ?? false)
            let coincideCat = filtroCategoria == nil || m.categoria?.id == filtroCategoria?.id
            let coincideCuenta = filtroCuenta == nil || m.cuenta?.id == filtroCuenta?.id
            return coincideTexto && coincideCat && coincideCuenta
        }
    }

    private var porDia: [(dia: Date, movimientos: [Movimiento])] {
        Dictionary(grouping: filtrados) { Calendar.current.startOfDay(for: $0.fecha) }
            .map { (dia: $0.key, movimientos: $0.value.sorted { $0.fecha > $1.fecha }) }
            .sorted { $0.dia > $1.dia }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filtrados.isEmpty {
                    ContentUnavailableView(
                        movimientos.isEmpty ? "Todavía no hay nada" : "Nada con ese filtro",
                        systemImage: "list.bullet.rectangle",
                        description: Text(movimientos.isEmpty
                                          ? "Registra tu primer gasto con el botón +."
                                          : "Prueba con otra búsqueda.")
                    )
                } else {
                    List {
                        ForEach(porDia, id: \.dia) { grupo in
                            Section {
                                ForEach(grupo.movimientos) { m in
                                    Button { editando = m } label: {
                                        FilaMovimiento(movimiento: m)
                                    }
                                    .buttonStyle(.plain)
                                    // Sin esto solo responde el texto, no la fila entera.
                                    .contentShape(Rectangle())
                                    .swipeActions(edge: .leading) {
                                        Button { editando = m } label: {
                                            Label("Editar", systemImage: "pencil")
                                        }
                                        .tint(.blue)
                                    }
                                }
                                .onDelete { borrar($0, en: grupo.movimientos) }
                            } header: {
                                HStack {
                                    Text(encabezadoDia(grupo.dia))
                                    Spacer()
                                    Text(pesos(Finanzas.totalGastos(grupo.movimientos), decimales: false))
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Movimientos")
            .searchable(text: $busqueda, prompt: "Buscar comercio, nota o categoría")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { menuFiltros }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { mostrandoCaptura = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $editando) { m in
                EditorMovimientoView(movimiento: m)
            }
        }
    }

    private var menuFiltros: some View {
        Menu {
            Menu("Categoría") {
                Button("Todas") { filtroCategoria = nil }
                ForEach(categorias) { c in
                    Button("\(c.emoji) \(c.nombre)") { filtroCategoria = c }
                }
            }
            Menu("Cuenta") {
                Button("Todas") { filtroCuenta = nil }
                ForEach(cuentas) { c in
                    Button(c.nombre) { filtroCuenta = c }
                }
            }
            if filtroCategoria != nil || filtroCuenta != nil {
                Divider()
                Button("Quitar filtros", role: .destructive) {
                    filtroCategoria = nil
                    filtroCuenta = nil
                }
            }
        } label: {
            Image(systemName: filtroCategoria == nil && filtroCuenta == nil
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
    }

    private func borrar(_ indices: IndexSet, en grupo: [Movimiento]) {
        for i in indices { contexto.delete(grupo[i]) }
        try? contexto.save()
    }
}

struct FilaMovimiento: View {
    let movimiento: Movimiento

    private var color: Color {
        switch movimiento.tipo {
        case .gasto: Color(hex: movimiento.categoria?.colorHex ?? "#8E8E93")
        case .ingreso: .green
        case .transferencia: .blue
        }
    }

    private var titulo: String {
        if !movimiento.comercio.isEmpty { return movimiento.comercio }
        if movimiento.tipo == .transferencia { return "Transferencia" }
        return movimiento.categoria?.nombre ?? "Sin categoría"
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(color.opacity(0.18)).frame(width: 38, height: 38)
                if movimiento.tipo == .gasto, let emoji = movimiento.categoria?.emoji {
                    Text(emoji)
                } else {
                    Image(systemName: movimiento.tipo.icono).foregroundStyle(color)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(.subheadline.weight(.medium)).lineLimit(1)
                HStack(spacing: 4) {
                    if !movimiento.comercio.isEmpty, let cat = movimiento.categoria {
                        Text(cat.nombre)
                    }
                    if let cuenta = movimiento.cuenta {
                        if !movimiento.comercio.isEmpty && movimiento.categoria != nil { Text("·") }
                        Text(cuenta.nombre)
                    }
                    if movimiento.creadoPorAtajo {
                        Image(systemName: "wand.and.stars").foregroundStyle(.purple)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(signo + pesos(movimiento.monto))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(movimiento.tipo == .ingreso ? .green : .primary)
                Text(movimiento.fecha.formatted(date: .omitted, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private var signo: String {
        switch movimiento.tipo {
        case .gasto: "−"
        case .ingreso: "+"
        case .transferencia: ""
        }
    }
}
