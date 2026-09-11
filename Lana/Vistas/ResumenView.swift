import SwiftUI
import SwiftData
import Charts

struct ResumenView: View {
    @Query private var movimientos: [Movimiento]
    @Query(sort: \Cuenta.orden) private var cuentas: [Cuenta]
    @Query private var suscripciones: [Suscripcion]
    @Query(sort: \Categoria.orden) private var categorias: [Categoria]

    @Binding var mostrandoCaptura: Bool
    @State private var mesVisible = Date()
    @State private var capturaRapida: Categoria?
    @State private var verTodasLasCategorias = false

    private var rango: ClosedRange<Date> { Finanzas.rangoDelMes(de: mesVisible) }
    private var delMes: [Movimiento] { Finanzas.movimientos(movimientos, en: rango) }
    private var gastoMes: Double { Finanzas.totalGastos(delMes) }
    private var ingresoMes: Double { Finanzas.totalIngresos(delMes) }

    private var gastoMesPasado: Double {
        guard let anterior = Calendar.current.date(byAdding: .month, value: -1, to: mesVisible) else { return 0 }
        return Finanzas.totalGastos(Finanzas.movimientos(movimientos, en: Finanzas.rangoDelMes(de: anterior)))
    }

    private var porCategoria: [Finanzas.GastoPorCategoria] { Finanzas.gastosPorCategoria(delMes) }
    private var patrimonio: Double { Finanzas.patrimonio(cuentas: cuentas, movimientos: movimientos) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    selectorMes
                    tarjetaPrincipal
                    registroRapido
                    if porCategoria.isEmpty {
                        vacio
                    } else {
                        graficaDona
                        listaCategorias
                        graficaPorDia
                        topComercios
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 90)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Resumen")
            .overlay(alignment: .bottomTrailing) { botonAgregar }
            .sheet(item: $capturaRapida) { categoria in
                EditorMovimientoView(categoriaInicial: categoria)
            }
        }
    }

    // MARK: - Piezas

    private var selectorMes: some View {
        HStack {
            Button { cambiarMes(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(nombreMes(mesVisible)).font(.headline)
            Spacer()
            Button { cambiarMes(1) } label: { Image(systemName: "chevron.right") }
                .disabled(esMesActual)
                .opacity(esMesActual ? 0.3 : 1)
        }
        .padding(.top, 4)
    }

    private var esMesActual: Bool {
        Calendar.current.isDate(mesVisible, equalTo: Date(), toGranularity: .month)
    }

    private func cambiarMes(_ delta: Int) {
        if let nuevo = Calendar.current.date(byAdding: .month, value: delta, to: mesVisible) {
            mesVisible = nuevo
        }
    }

    /// Las 6 categorías que más usas, para capturar de un tap.
    private var categoriasFrecuentes: [Categoria] {
        let deGasto = categorias.filter { !$0.esIngreso }
        let conteo = Dictionary(grouping: movimientos.filter { $0.tipo == .gasto }) { $0.categoria?.id }
            .mapValues(\.count)
        let ordenadas = deGasto.sorted {
            (conteo[$0.id] ?? 0, -$0.orden) > (conteo[$1.id] ?? 0, -$1.orden)
        }
        return Array(ordenadas.prefix(6))
    }

    private var registroRapido: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Registro rápido")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(categoriasFrecuentes) { c in
                        Button {
                            capturaRapida = c
                        } label: {
                            VStack(spacing: 4) {
                                Text(c.emoji).font(.title3)
                                Text(c.nombre)
                                    .font(.system(size: 10))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 76, height: 68)
                            .padding(.horizontal, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(hex: c.colorHex).opacity(0.14))
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        mostrandoCaptura = true
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "ellipsis").font(.title3)
                            Text("Otro").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        .frame(width: 76, height: 68)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.tertiarySystemFill)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 2)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var tarjetaPrincipal: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text("Gastado este mes")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(pesos(gastoMes))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                comparativaMesPasado
            }

            Divider()

            HStack {
                miniDato("Ingresos", pesos(ingresoMes, decimales: false), .green)
                Divider().frame(height: 32)
                miniDato("Balance", pesos(ingresoMes - gastoMes, decimales: false),
                         ingresoMes - gastoMes >= 0 ? .green : .red)
                Divider().frame(height: 32)
                miniDato("Patrimonio", pesosCortos(patrimonio), .primary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var comparativaMesPasado: some View {
        if gastoMesPasado > 0 {
            let delta = gastoMes - gastoMesPasado
            let pct = delta / gastoMesPasado * 100
            HStack(spacing: 4) {
                Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                Text("\(porcentaje(abs(pct), decimales: 0)) vs. mes pasado")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(delta >= 0 ? .red : .green)
        }
    }

    private func miniDato(_ titulo: String, _ valor: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(titulo).font(.caption2).foregroundStyle(.secondary)
            Text(valor).font(.subheadline.weight(.semibold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    private var graficaDona: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("En qué se te fue").font(.headline)
            Chart(porCategoria) { item in
                SectorMark(
                    angle: .value("Monto", item.total),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.5
                )
                .cornerRadius(5)
                .foregroundStyle(Color(hex: item.colorHex))
            }
            .frame(height: 210)
            .overlay {
                VStack(spacing: 0) {
                    Text(porCategoria.first?.emoji ?? "").font(.title2)
                    Text(porCategoria.first?.nombre ?? "")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(pesosCortos(porCategoria.first?.total ?? 0))
                        .font(.headline)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    /// Lo gastado por categoría; con "ver todas" también salen las que van en cero.
    private var desglose: [Finanzas.GastoPorCategoria] {
        guard verTodasLasCategorias else { return porCategoria }
        let usadas = Set(porCategoria.compactMap { $0.categoria?.id })
        let enCero = categorias
            .filter { !$0.esIngreso && !usadas.contains($0.id) }
            .sorted { $0.orden < $1.orden }
            .map { Finanzas.GastoPorCategoria(categoria: $0, total: 0) }
        return porCategoria + enCero
    }

    private var listaCategorias: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Desglose por categoría").font(.headline)
                Spacer()
                Button(verTodasLasCategorias ? "Ver menos" : "Ver todas") {
                    withAnimation(.snappy) { verTodasLasCategorias.toggle() }
                }
                .font(.caption.weight(.medium))
            }
            .padding(.bottom, 2)

            ForEach(desglose) { item in
                NavigationLink {
                    DetalleCategoriaView(categoria: item.categoria, rango: rango)
                } label: {
                    filaCategoria(item)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func filaCategoria(_ item: Finanzas.GastoPorCategoria) -> some View {
        let presupuesto = item.categoria?.presupuestoMensual ?? 0
        let proporcion = gastoMes > 0 ? item.total / gastoMes : 0
        let vacia = item.total == 0
        return VStack(spacing: 6) {
            HStack {
                Text(item.emoji)
                Text(item.nombre).font(.subheadline)
                Spacer()
                Text(pesos(item.total, decimales: false)).font(.subheadline.weight(.semibold))
                Text(vacia ? "—" : porcentaje(proporcion * 100, decimales: 0))
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }
            .opacity(vacia ? 0.45 : 1)

            if !vacia {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.tertiarySystemFill)).frame(height: 6)
                        Capsule()
                            .fill(Color(hex: item.colorHex))
                            .frame(width: max(4, geo.size.width * proporcion), height: 6)
                    }
                }
                .frame(height: 6)
            }
            if presupuesto > 0 {
                HStack {
                    Spacer()
                    Text(item.total > presupuesto
                         ? "Te pasaste \(pesos(item.total - presupuesto, decimales: false)) del presupuesto"
                         : "Te quedan \(pesos(presupuesto - item.total, decimales: false)) de \(pesos(presupuesto, decimales: false))")
                    .font(.caption2)
                    .foregroundStyle(item.total > presupuesto ? .red : .secondary)
                }
            }
        }
    }

    private var graficaPorDia: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Día por día").font(.headline)
            Chart(Finanzas.gastosPorDia(delMes)) { punto in
                BarMark(
                    x: .value("Día", punto.dia, unit: .day),
                    y: .value("Gasto", punto.total)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(3)
            }
            .chartYAxis {
                AxisMarks { valor in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = valor.as(Double.self) { Text(pesosCortos(v)) }
                    }
                }
            }
            .frame(height: 150)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var topComercios: some View {
        let top = Array(Finanzas.gastosPorComercio(delMes).prefix(6))
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Dónde más dejas la lana").font(.headline)
                ForEach(top) { c in
                    HStack {
                        Text(c.comercio).font(.subheadline)
                        Text("×\(c.veces)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(pesos(c.total, decimales: false)).font(.subheadline.weight(.medium))
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var vacio: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray").font(.largeTitle).foregroundStyle(.secondary)
            Text("Sin gastos en \(nombreMes(mesVisible))")
                .font(.headline)
            Text("Dale al + para registrar el primero.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    private var botonAgregar: some View {
        Button {
            mostrandoCaptura = true
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Circle().fill(Color.accentColor).shadow(radius: 6, y: 3))
        }
        .padding(.trailing, 20)
        .padding(.bottom, 16)
    }
}

/// Lista los movimientos de una categoría dentro del mes que estás viendo.
struct DetalleCategoriaView: View {
    @Environment(\.modelContext) private var contexto
    @Query private var movimientos: [Movimiento]
    let categoria: Categoria?
    let rango: ClosedRange<Date>

    @State private var editando: Movimiento?

    private var lista: [Movimiento] {
        Finanzas.movimientos(movimientos, en: rango)
            .filter { $0.tipo == .gasto && $0.categoria?.id == categoria?.id }
            .sorted { $0.fecha > $1.fecha }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Total")
                    Spacer()
                    Text(pesos(lista.reduce(0) { $0 + $1.monto })).fontWeight(.semibold)
                }
                HStack {
                    Text("Movimientos")
                    Spacer()
                    Text("\(lista.count)").foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(lista) { m in
                    Button { editando = m } label: {
                        FilaMovimiento(movimiento: m)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
                .onDelete { indices in
                    for i in indices { contexto.delete(lista[i]) }
                    try? contexto.save()
                }
            } footer: {
                Text("Toca cualquiera para editarlo o desliza para borrarlo.")
            }
        }
        .navigationTitle(categoria?.nombre ?? "Sin categoría")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editando) { m in
            EditorMovimientoView(movimiento: m)
        }
    }
}
