import SwiftUI
import SwiftData

struct SuscripcionesView: View {
    @Environment(\.modelContext) private var contexto
    @Query private var suscripciones: [Suscripcion]
    @Query(sort: \Cuenta.orden) private var cuentas: [Cuenta]

    @State private var creando = false
    @State private var editando: Suscripcion?

    private var activas: [Suscripcion] {
        suscripciones.filter(\.activa).sorted { $0.proximoCobro < $1.proximoCobro }
    }
    private var pausadas: [Suscripcion] { suscripciones.filter { !$0.activa } }
    private var totalMensual: Double { Finanzas.costoMensualTotal(suscripciones) }

    var body: some View {
        ScrollView {
                VStack(spacing: 16) {
                    if suscripciones.isEmpty {
                        ContentUnavailableView(
                            "Sin suscripciones",
                            systemImage: "repeat",
                            description: Text("Netflix, Spotify, el gym, iCloud… agrégalas y ve cuánto se te va cada mes sin que lo notes.")
                        )
                        .padding(.top, 60)
                    } else {
                        tarjetaTotal
                        seccion("Próximos cobros", activas)
                        if !pausadas.isEmpty { seccion("Pausadas", pausadas) }
                    }
                }
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Suscripciones")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creando = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $creando) { EditorSuscripcionView() }
        .sheet(item: $editando) { s in EditorSuscripcionView(suscripcion: s) }
    }

    private var tarjetaTotal: some View {
        VStack(spacing: 6) {
            Text("Se te van cada mes").font(.subheadline).foregroundStyle(.secondary)
            Text(pesos(totalMensual))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
            Text("\(pesos(totalMensual * 12, decimales: false)) al año · \(activas.count) activas")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func seccion(_ titulo: String, _ lista: [Suscripcion]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(titulo).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(lista) { s in
                Button { editando = s } label: { fila(s) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            registrarCobro(s)
                        } label: {
                            Label("Ya me lo cobraron", systemImage: "checkmark.circle")
                        }
                        Button {
                            s.activa.toggle()
                            try? contexto.save()
                        } label: {
                            Label(s.activa ? "Pausar" : "Reactivar", systemImage: s.activa ? "pause" : "play")
                        }
                        Button(role: .destructive) {
                            contexto.delete(s)
                            try? contexto.save()
                        } label: {
                            Label("Borrar", systemImage: "trash")
                        }
                    }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func fila(_ s: Suscripcion) -> some View {
        let dias = s.diasParaCobro
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: s.categoria?.colorHex ?? "#BF5AF2").opacity(0.18))
                    .frame(width: 38, height: 38)
                Text(s.categoria?.emoji ?? "🔁")
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(s.nombre).font(.subheadline.weight(.medium))
                Text(textoCobro(dias, ciclo: s.ciclo))
                    .font(.caption)
                    .foregroundStyle(dias <= 3 && s.activa ? .orange : .secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(pesos(s.monto, decimales: false)).font(.subheadline.weight(.semibold))
                if s.ciclo != .mensual {
                    Text("≈\(pesos(s.costoMensual, decimales: false))/mes")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .opacity(s.activa ? 1 : 0.5)
    }

    private func textoCobro(_ dias: Int, ciclo: CicloCobro) -> String {
        switch dias {
        case ..<0: "Vencido · \(ciclo.nombre)"
        case 0: "Hoy · \(ciclo.nombre)"
        case 1: "Mañana · \(ciclo.nombre)"
        default: "En \(dias) días · \(ciclo.nombre)"
        }
    }

    /// Crea el gasto real y adelanta la suscripción al siguiente periodo.
    private func registrarCobro(_ s: Suscripcion) {
        let cuenta = cuentas.first { $0.id == s.cuentaID }
        let mov = Movimiento(
            monto: s.monto,
            fecha: s.proximoCobro,
            tipo: .gasto,
            comercio: s.nombre,
            nota: "Suscripción \(s.ciclo.nombre.lowercased())",
            cuenta: cuenta,
            categoria: s.categoria
        )
        contexto.insert(mov)
        s.proximoCobro = s.ciclo.siguienteFecha(desde: s.proximoCobro)
        try? contexto.save()
    }
}

struct EditorSuscripcionView: View {
    @Environment(\.modelContext) private var contexto
    @Environment(\.dismiss) private var cerrar

    @Query(sort: \Categoria.orden) private var categorias: [Categoria]
    @Query(sort: \Cuenta.orden) private var cuentas: [Cuenta]

    var suscripcion: Suscripcion?

    @State private var nombre = ""
    @State private var monto = ""
    @State private var ciclo: CicloCobro = .mensual
    @State private var proximoCobro = Date()
    @State private var categoriaSel: Categoria?
    @State private var cuentaSel: Cuenta?
    @State private var cargado = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Netflix, gym, iCloud…", text: $nombre)
                    HStack {
                        Text("Monto")
                        Spacer()
                        TextField("0", text: $monto)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .conBotonListo()
                    }
                    Picker("Cada", selection: $ciclo) {
                        ForEach(CicloCobro.allCases) { c in Text(c.nombre).tag(c) }
                    }
                    DatePicker("Próximo cobro", selection: $proximoCobro, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "es_MX"))
                }

                Section {
                    Picker("Categoría", selection: $categoriaSel) {
                        Text("Ninguna").tag(nil as Categoria?)
                        ForEach(categorias.filter { !$0.esIngreso }) { c in
                            Text("\(c.emoji) \(c.nombre)").tag(c as Categoria?)
                        }
                    }
                    Picker("Se cobra a", selection: $cuentaSel) {
                        Text("Ninguna").tag(nil as Cuenta?)
                        ForEach(cuentas.filter(\.activa)) { c in
                            Text(c.nombre).tag(c as Cuenta?)
                        }
                    }
                }

                if let s = suscripcion {
                    Section {
                        Button("Borrar", role: .destructive) {
                            contexto.delete(s)
                            try? contexto.save()
                            cerrar()
                        }
                    }
                }
            }
            .navigationTitle(suscripcion == nil ? "Nueva suscripción" : "Editar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: guardar)
                        .fontWeight(.semibold)
                        .disabled(nombre.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: cargar)
        }
    }

    private func cargar() {
        guard !cargado else { return }
        cargado = true
        guard let s = suscripcion else {
            categoriaSel = categorias.first { $0.nombre == "Suscripciones" }
            return
        }
        nombre = s.nombre
        monto = String(s.monto)
        ciclo = s.ciclo
        proximoCobro = s.proximoCobro
        categoriaSel = s.categoria
        cuentaSel = cuentas.first { $0.id == s.cuentaID }
    }

    private func guardar() {
        let valor = Double(monto.replacingOccurrences(of: ",", with: ".")) ?? 0
        if let s = suscripcion {
            s.nombre = nombre
            s.monto = valor
            s.ciclo = ciclo
            s.proximoCobro = proximoCobro
            s.categoria = categoriaSel
            s.cuentaID = cuentaSel?.id
        } else {
            let nueva = Suscripcion(nombre: nombre, monto: valor, ciclo: ciclo,
                                    proximoCobro: proximoCobro, cuentaID: cuentaSel?.id,
                                    categoria: categoriaSel)
            contexto.insert(nueva)
        }
        try? contexto.save()
        cerrar()
    }
}
