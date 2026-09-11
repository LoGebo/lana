import SwiftUI
import SwiftData
import Charts
import WidgetKit

struct CuentasView: View {
    @Environment(\.modelContext) private var contexto
    @Query(sort: \Cuenta.orden) private var cuentas: [Cuenta]
    @Query private var movimientos: [Movimiento]

    @State private var pestaña = 0
    @State private var editando: Cuenta?
    @State private var creando = false

    private var activas: [Cuenta] { cuentas.filter(\.activa) }
    private var patrimonio: Double { Finanzas.patrimonio(cuentas: cuentas, movimientos: movimientos) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Vista", selection: $pestaña) {
                    Text("Cuentas").tag(0)
                    Text("Inversiones").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                if pestaña == 0 {
                    listaCuentas
                } else {
                    InversionesView(cuentas: activas, movimientos: movimientos, alEditar: { editando = $0 })
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Mi lana")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creando = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $creando) { EditorCuentaView() }
            .sheet(item: $editando) { c in EditorCuentaView(cuenta: c) }
        }
    }

    private var listaCuentas: some View {
        ScrollView {
            VStack(spacing: 16) {
                tarjetaPatrimonio

                ForEach(TipoCuenta.allCases) { tipo in
                    let delTipo = activas.filter { $0.tipo == tipo }
                    if !delTipo.isEmpty {
                        seccion(tipo: tipo, cuentas: delTipo)
                    }
                }

                let inactivas = cuentas.filter { !$0.activa }
                if !inactivas.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Archivadas").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(inactivas) { c in
                            Button { editando = c } label: {
                                HStack {
                                    Text(c.nombre).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(pesos(Finanzas.saldo(de: c, movimientos: movimientos), decimales: false))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
    }

    private var tarjetaPatrimonio: some View {
        VStack(spacing: 6) {
            Text("Patrimonio total").font(.subheadline).foregroundStyle(.secondary)
            Text(pesos(patrimonio))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
            let deuda = activas.filter { $0.tipo == .credito }
                .reduce(0.0) { $0 + min(0, Finanzas.saldo(de: $1, movimientos: movimientos)) }
            if deuda < 0 {
                Text("Incluye \(pesos(abs(deuda), decimales: false)) de deuda en tarjetas")
                    .font(.caption).foregroundStyle(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func seccion(tipo: TipoCuenta, cuentas lista: [Cuenta]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(tipo.nombre, systemImage: tipo.icono)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(pesos(lista.reduce(0) { $0 + Finanzas.saldo(de: $1, movimientos: movimientos) }, decimales: false))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ForEach(lista) { c in
                Button { editando = c } label: { filaCuenta(c) }
                    .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func filaCuenta(_ c: Cuenta) -> some View {
        let saldo = Finanzas.saldo(de: c, movimientos: movimientos)
        return HStack(spacing: 12) {
            LogoCuenta(nombre: c.nombre, institucion: c.institucion,
                       respaldoColor: c.colorHex, simboloTipo: c.tipo.icono)

            VStack(alignment: .leading, spacing: 1) {
                Text(c.nombre).font(.subheadline.weight(.medium))
                if c.rendimientoAnual > 0 {
                    Text("\(porcentaje(c.rendimientoAnual)) anual")
                        .font(.caption).foregroundStyle(.green)
                } else if !c.institucion.isEmpty {
                    Text(c.institucion).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(pesos(saldo))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(saldo < 0 ? .red : .primary)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Editor de cuenta

struct EditorCuentaView: View {
    @Environment(\.modelContext) private var contexto
    @Environment(\.dismiss) private var cerrar

    var cuenta: Cuenta?

    @State private var nombre = ""
    @State private var institucion = ""
    @State private var tipo: TipoCuenta = .debito
    @State private var saldoInicial = ""
    @State private var rendimiento = ""
    @State private var colorHex = paletaLana[0]
    @State private var activa = true
    @State private var acumula = true
    @State private var notas = ""
    @State private var saldoOriginal = ""
    @State private var confirmandoBorrado = false
    @State private var cargado = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre (Mercado Pago, BBVA…)", text: $nombre)
                    TextField("Institución (opcional)", text: $institucion)
                    Picker("Tipo", selection: $tipo) {
                        ForEach(TipoCuenta.allCases) { t in
                            Label(t.nombre, systemImage: t.icono).tag(t)
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Saldo actual")
                        Spacer()
                        TextField("0", text: $saldoInicial)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .conBotonListo()
                    }
                } footer: {
                    Text(tipo == .credito
                         ? "En tarjetas de crédito pon lo que debes en negativo, por ejemplo −3500."
                         : "Lo que tienes hoy en esta cuenta. A partir de aquí la app suma y resta sola.")
                }

                Section {
                    HStack {
                        Text("Rendimiento anual")
                        Spacer()
                        TextField("0", text: $rendimiento)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .conBotonListo()
                        Text("%").foregroundStyle(.secondary)
                    }
                    if (Double(rendimiento.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0 {
                        Toggle("Sumar el rendimiento solo", isOn: $acumula)
                    }
                } footer: {
                    Text("El GAT o tasa que te da la cuenta. Mercado Pago, Nu, DiDi, Revolut… Déjalo en 0 si no genera nada.\n\nCon el rendimiento activado, el saldo va creciendo día con día igual que en tu banco, así que no registres los intereses como ingreso. Si tu banco marca otro número, corrige el saldo aquí y la cuenta vuelve a arrancar desde hoy.")
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(paletaLana, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(height: 32)
                                .overlay {
                                    if hex == colorHex {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { colorHex = hex }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    TextField("Notas", text: $notas, axis: .vertical)
                    Toggle("Activa", isOn: $activa)
                }

                if cuenta != nil {
                    Section {
                        Button("Borrar cuenta", role: .destructive) { confirmandoBorrado = true }
                    } footer: {
                        Text("Los movimientos de esta cuenta se quedan, pero sin cuenta asignada.")
                    }
                }
            }
            .navigationTitle(cuenta == nil ? "Nueva cuenta" : "Editar cuenta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: guardar)
                        .fontWeight(.semibold)
                        .disabled(nombre.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("¿Seguro?", isPresented: $confirmandoBorrado, titleVisibility: .visible) {
                Button("Borrar", role: .destructive) {
                    if let c = cuenta { contexto.delete(c); try? contexto.save() }
                    cerrar()
                }
            }
            .onAppear(perform: cargar)
        }
    }

    private func cargar() {
        guard !cargado else { return }
        cargado = true
        guard let c = cuenta else { return }
        nombre = c.nombre
        institucion = c.institucion
        tipo = c.tipo
        saldoInicial = c.saldoInicial == 0 ? "" : String(c.saldoInicial)
        saldoOriginal = saldoInicial
        acumula = c.acumulaRendimiento
        rendimiento = c.rendimientoAnual == 0 ? "" : String(c.rendimientoAnual)
        colorHex = c.colorHex
        activa = c.activa
        notas = c.notas
    }

    private func guardar() {
        let saldo = Double(saldoInicial.replacingOccurrences(of: ",", with: ".")) ?? 0
        let tasa = Double(rendimiento.replacingOccurrences(of: ",", with: ".")) ?? 0

        if let c = cuenta {
            // Si corriges el saldo, el rendimiento vuelve a contar desde hoy:
            // ese número nuevo ya trae los intereses que llevabas.
            if saldoInicial != saldoOriginal {
                c.fechaBase = Date()
            }
            c.nombre = nombre
            c.institucion = institucion
            c.tipo = tipo
            c.saldoInicial = saldo
            c.rendimientoAnual = tasa
            c.colorHex = colorHex
            c.activa = activa
            c.acumulaRendimiento = acumula
            c.notas = notas
        } else {
            let nueva = Cuenta(nombre: nombre, institucion: institucion, tipo: tipo,
                               saldoInicial: saldo, rendimientoAnual: tasa, colorHex: colorHex, orden: 99)
            nueva.notas = notas
            nueva.acumulaRendimiento = acumula
            nueva.fechaBase = Date()
            contexto.insert(nueva)
        }
        try? contexto.save()
        WidgetCenter.shared.reloadAllTimelines()
        cerrar()
    }
}
