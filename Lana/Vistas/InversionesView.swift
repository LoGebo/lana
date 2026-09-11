import SwiftUI
import Charts

struct InversionesView: View {
    let cuentas: [Cuenta]
    let movimientos: [Movimiento]
    var alEditar: (Cuenta) -> Void

    @State private var mesesProyeccion = 12

    private var invertidas: [Cuenta] {
        cuentas.filter { $0.rendimientoAnual > 0 || $0.tipo == .inversion }
            .sorted { saldo($0) > saldo($1) }
    }

    private func saldo(_ c: Cuenta) -> Double { Finanzas.saldo(de: c, movimientos: movimientos) }

    private var total: Double { invertidas.reduce(0) { $0 + max(0, saldo($1)) } }
    private var generado: Double { Finanzas.rendimientoAcumulado(cuentas: cuentas, movimientos: movimientos) }
    private var hoyGenera: Double { Finanzas.rendimientoDeHoy(cuentas: cuentas, movimientos: movimientos) }
    private var desde: Date? { Finanzas.inicioDelRendimiento(cuentas: cuentas) }
    private var tasaPromedio: Double { Finanzas.tasaPonderada(cuentas: cuentas, movimientos: movimientos) }
    private var alAño: Double { Finanzas.rendimiento(saldo: total, tasaAnual: tasaPromedio, dias: 365) }
    private var alMes: Double { alAño / 12 }
    private var alDia: Double { hoyGenera }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if invertidas.isEmpty {
                    ContentUnavailableView(
                        "Sin cuentas de inversión",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Crea una cuenta tipo Inversión y ponle su rendimiento anual.")
                    )
                    .padding(.top, 40)
                } else {
                    tarjetaTotal
                    if total > 0 { graficaDistribucion }
                    listaCuentas
                    if total > 0 { proyeccion }
                    notaISR
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
    }

    private var tarjetaTotal: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text("Invertido").font(.subheadline).foregroundStyle(.secondary)
                Text(pesos(total))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                Text("a \(porcentaje(tasaPromedio)) anual promedio")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            }

            Divider()

            HStack {
                dato("Hoy", alDia)
                Divider().frame(height: 34)
                dato("Al mes", alMes)
                Divider().frame(height: 34)
                dato("Al año", alAño)
            }

            if let desde {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Llevas generados")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("+" + pesos(generado))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.green)
                        .contentTransition(.numericText())
                }
                Text("desde el \(fechaCorta(desde)) · se suma solo cada día")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func dato(_ titulo: String, _ valor: Double) -> some View {
        VStack(spacing: 2) {
            Text(titulo).font(.caption2).foregroundStyle(.secondary)
            Text("+" + pesos(valor, decimales: valor < 100))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
        }
        .frame(maxWidth: .infinity)
    }

    private var graficaDistribucion: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cómo está repartida").font(.headline)
            Chart(invertidas.filter { saldo($0) > 0 }) { c in
                SectorMark(
                    angle: .value("Saldo", saldo(c)),
                    innerRadius: .ratio(0.6),
                    angularInset: 1.5
                )
                .cornerRadius(5)
                .foregroundStyle(Color(hex: Marcas.color(para: c.nombre, institucion: c.institucion, respaldo: c.colorHex)))
            }
            .frame(height: 190)

            ForEach(invertidas.filter { saldo($0) > 0 }) { c in
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: Marcas.color(para: c.nombre, institucion: c.institucion, respaldo: c.colorHex)))
                        .frame(width: 9, height: 9)
                    Text(c.nombre).font(.caption)
                    Spacer()
                    Text(porcentaje(total > 0 ? saldo(c) / total * 100 : 0, decimales: 0))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var listaCuentas: some View {
        VStack(spacing: 14) {
            ForEach(invertidas) { c in
                Button { alEditar(c) } label: { fila(c) }
                    .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func fila(_ c: Cuenta) -> some View {
        let s = saldo(c)
        let genera = Finanzas.rendimiento(saldo: max(0, s), tasaAnual: c.rendimientoAnual, dias: 30.4)
        return HStack(spacing: 12) {
            LogoCuenta(nombre: c.nombre, institucion: c.institucion,
                       respaldoColor: c.colorHex, simboloTipo: c.tipo.icono)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(c.nombre).font(.subheadline.weight(.medium))
                    if c.rendimientoAnual > 0 {
                        Text(porcentaje(c.rendimientoAnual, decimales: c.rendimientoAnual == c.rendimientoAnual.rounded() ? 0 : 1))
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.green.opacity(0.15)))
                            .foregroundStyle(.green)
                    }
                }
                HStack(spacing: 5) {
                    if c.rendimientoAnual > 0 {
                        Text("+\(pesos(genera, decimales: false)) al mes")
                        let ganado = Finanzas.rendimientoGenerado(de: c, movimientos: movimientos)
                        if ganado >= 0.01 {
                            Text("·")
                            Text("ya \(pesos(ganado)) generados")
                        }
                    } else {
                        Text("Sin rendimiento configurado")
                    }
                }
                .font(.caption)
                .foregroundStyle(c.rendimientoAnual > 0 ? .green : .orange)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }

            Spacer()

            Text(pesos(s, decimales: false)).font(.subheadline.weight(.semibold))
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var proyeccion: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Si no le mueves").font(.headline)
                Spacer()
                Picker("", selection: $mesesProyeccion) {
                    Text("1 año").tag(12)
                    Text("3 años").tag(36)
                    Text("5 años").tag(60)
                }
                .pickerStyle(.menu)
            }

            let puntos = Finanzas.proyeccion(saldo: total, tasaAnual: tasaPromedio, meses: mesesProyeccion)
            // El área arranca en el piso de la escala; si arranca en cero se
            // sale del dominio y se ve cortada.
            let piso = total * 0.97
            let techo = (puntos.last?.monto ?? total) * 1.02

            Chart(puntos) { p in
                AreaMark(
                    x: .value("Mes", p.mes),
                    yStart: .value("Base", piso),
                    yEnd: .value("Monto", p.monto)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.green.opacity(0.30), .green.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(x: .value("Mes", p.mes), y: .value("Monto", p.monto))
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: piso...techo)
            .chartXScale(domain: 0...mesesProyeccion)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { valor in
                    AxisGridLine()
                    AxisValueLabel {
                        if let m = valor.as(Int.self) {
                            Text(m == 0 ? "hoy" : "\(m)m")
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { valor in
                    AxisGridLine()
                    AxisValueLabel { if let v = valor.as(Double.self) { Text(pesosCortos(v)) } }
                }
            }
            .frame(height: 160)

            if let fin = puntos.last {
                HStack {
                    Text("En \(mesesProyeccion / 12) año\(mesesProyeccion > 12 ? "s" : "") tendrías")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(pesos(fin.monto, decimales: false)).font(.subheadline.weight(.semibold))
                    Text("(+\(pesos(fin.monto - total, decimales: false)))")
                        .font(.caption).foregroundStyle(.green)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var notaISR: some View {
        Text("Ojo: son tasas brutas con interés compuesto mensual. En México te retienen ISR sobre el capital, así que lo que te llega es un poco menos.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }
}
