import SwiftUI
import SwiftData
import CoreTransferable
import UniformTypeIdentifiers

struct AjustesView: View {
    @Environment(\.modelContext) private var contexto
    @Query(sort: \Categoria.orden) private var categorias: [Categoria]
    @Query(sort: \Movimiento.fecha, order: .reverse) private var movimientos: [Movimiento]
    @Query(sort: \Cuenta.orden) private var cuentas: [Cuenta]

    @State private var creandoCategoria = false
    @State private var cuentaGastos: UUID? = Preferencias.cuentaParaGastos

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Se carga a", selection: $cuentaGastos) {
                        Text("La última que usé").tag(nil as UUID?)
                        ForEach(cuentas.filter(\.activa)) { c in
                            Text(c.nombre).tag(c.id as UUID?)
                        }
                    }
                    .onChange(of: cuentaGastos) { _, nueva in
                        Preferencias.cuentaParaGastos = nueva
                    }
                } header: {
                    Text("Cuenta por defecto")
                } footer: {
                    Text("Con cuál arranca cada gasto nuevo, incluidos los que registras por Siri. Siempre puedes cambiarla en la captura.")
                }

                Section("Categorías") {
                    ForEach(categorias) { c in
                        NavigationLink {
                            EditorCategoriaView(categoria: c)
                        } label: {
                            HStack {
                                Text(c.emoji)
                                Text(c.nombre)
                                Spacer()
                                if c.presupuestoMensual > 0 {
                                    Text(pesos(c.presupuestoMensual, decimales: false))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Circle().fill(Color(hex: c.colorHex)).frame(width: 10, height: 10)
                            }
                        }
                    }
                    .onDelete { indices in
                        for i in indices { contexto.delete(categorias[i]) }
                        try? contexto.save()
                    }

                    Button {
                        creandoCategoria = true
                    } label: {
                        Label("Nueva categoría", systemImage: "plus.circle")
                    }
                }

                Section {
                    NavigationLink {
                        GuiaApplePayView()
                    } label: {
                        Label("Registrar más rápido", systemImage: "wand.and.stars")
                    }
                } footer: {
                    Text("Siri, toque atrás, Centro de Control y Apple Pay: todas las formas de capturar un gasto en 2 segundos.")
                }

                Section {
                    ShareLink(
                        item: ArchivoCSV(texto: generarCSV()),
                        preview: SharePreview("Movimientos de Lana")
                    ) {
                        Label("Exportar CSV", systemImage: "square.and.arrow.up")
                    }
                } footer: {
                    Text("\(movimientos.count) movimientos. Ábrelo en Numbers o Excel cuando quieras hacer cuentas más finas.")
                }

                Section {
                    LabeledContent("Versión", value: "1.0")
                    LabeledContent("Datos", value: "Solo en este iPhone")
                } footer: {
                    Text("Nada sale de tu teléfono. Si quieres respaldo, activa iCloud Backup o exporta el CSV de vez en cuando.")
                }
            }
            .navigationTitle("Ajustes")
            .sheet(isPresented: $creandoCategoria) {
                NavigationStack { EditorCategoriaView() }
            }
        }
    }

    private func generarCSV() -> String {
        var lineas = ["fecha,tipo,monto,categoria,cuenta,comercio,nota"]
        let formato = ISO8601DateFormatter()
        for m in movimientos {
            let campos = [
                formato.string(from: m.fecha),
                m.tipo.rawValue,
                String(format: "%.2f", m.monto),
                m.categoria?.nombre ?? "",
                m.cuenta?.nombre ?? "",
                m.comercio,
                m.nota
            ].map { "\"\($0.replacingOccurrences(of: "\"", with: "'"))\"" }
            lineas.append(campos.joined(separator: ","))
        }
        return lineas.joined(separator: "\n")
    }
}

struct ArchivoCSV: Transferable {
    let texto: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { archivo in
            Data(archivo.texto.utf8)
        }
        .suggestedFileName("lana-movimientos.csv")
    }
}

// MARK: - Editor de categoría

struct EditorCategoriaView: View {
    @Environment(\.modelContext) private var contexto
    @Environment(\.dismiss) private var cerrar

    var categoria: Categoria?

    @State private var nombre = ""
    @State private var emoji = "📦"
    @State private var colorHex = paletaLana[0]
    @State private var presupuesto = ""
    @State private var esIngreso = false
    @State private var cargado = false

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("😀", text: $emoji)
                        .font(.title)
                        .frame(width: 50)
                        .onChange(of: emoji) { _, nuevo in
                            if nuevo.count > 2 { emoji = String(nuevo.suffix(1)) }
                        }
                    TextField("Nombre", text: $nombre)
                }
                Toggle("Es de ingresos", isOn: $esIngreso)
            }

            Section {
                HStack {
                    Text("Presupuesto mensual")
                    Spacer()
                    TextField("0", text: $presupuesto)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .conBotonListo()
                }
            } footer: {
                Text("Opcional. Si lo pones, el resumen te avisa cuánto te queda y cuándo te pasaste.")
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
        }
        .navigationTitle(categoria == nil ? "Nueva categoría" : nombre)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar", action: guardar)
                    .fontWeight(.semibold)
                    .disabled(nombre.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear(perform: cargar)
    }

    private func cargar() {
        guard !cargado else { return }
        cargado = true
        guard let c = categoria else { return }
        nombre = c.nombre
        emoji = c.emoji
        colorHex = c.colorHex
        presupuesto = c.presupuestoMensual == 0 ? "" : String(c.presupuestoMensual)
        esIngreso = c.esIngreso
    }

    private func guardar() {
        let monto = Double(presupuesto.replacingOccurrences(of: ",", with: ".")) ?? 0
        if let c = categoria {
            c.nombre = nombre
            c.emoji = emoji
            c.colorHex = colorHex
            c.presupuestoMensual = monto
            c.esIngreso = esIngreso
        } else {
            contexto.insert(Categoria(nombre: nombre, emoji: emoji, colorHex: colorHex,
                                      presupuestoMensual: monto, esIngreso: esIngreso, orden: 50))
        }
        try? contexto.save()
        cerrar()
    }
}

// MARK: - Guía de Apple Pay

struct GuiaApplePayView: View {
    var body: some View {
        List {
            Section {
                Text("iOS no deja que ninguna app lea tus compras de Apple Pay ni las notificaciones de tu banco. Nadie puede, ni con permisos especiales. Lo que sí se puede es capturar en segundos, de estas cinco formas.")
                    .font(.subheadline)
            }

            Section {
                Text("Di: “Oye Siri, registra un gasto en Lana”.\n\nTiene que llevar la palabra Lana: así es como Siri sabe a qué app le hablas. Sin eso no funciona, no importa cómo lo digas.")
                    .font(.subheadline)
                Text("También jala:\n• “Oye Siri, registra un gasto de novia en Lana”\n• “Oye Siri, anota un gasto de transporte en Lana”\n• “Oye Siri, cuánto llevo gastado en Lana”\n• “Oye Siri, cuánta lana tengo en Lana”")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Cuando le dices la categoría, Siri solo te pregunta el monto y ya. Si dices el comercio (OXXO, Uber, Mercado Libre) la app le pone la categoría sola.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Opción 1 · Siri")
            }

            Section("Opción 2 · Tocando atrás del iPhone") {
                paso(1, "Abre Atajos → pestaña Atajos → botón +.")
                paso(2, "Agrega la acción Abrir captura rápida (de Lana) y ponle de nombre “Gasto”.")
                paso(3, "Ve a Ajustes → Accesibilidad → Tocar → Tocar atrás.")
                paso(4, "Escoge Doble toque (o Triple toque) y elige el atajo “Gasto”.")
                paso(5, "Listo: dos golpecitos atrás del teléfono y se abre la captura.")
            }

            Section("Opción 3 · Centro de Control") {
                paso(1, "Desliza desde arriba a la derecha para abrir el Centro de Control.")
                paso(2, "Mantén presionado y dale a + Agregar control.")
                paso(3, "Busca Registrar gasto y agrégalo.")
                paso(4, "También puedes ponerlo en la pantalla bloqueada, donde la linterna.")
            }

            Section("Opción 4 · Automático al pagar con Apple Pay") {
                paso(1, "Abre la app Atajos y ve a Automatización.")
                paso(2, "Toca +, elige Transacción.")
                paso(3, "Escoge la tarjeta de Wallet que más usas (o Cualquier tarjeta).")
                paso(4, "Elige Ejecutar inmediatamente y dale Siguiente.")
                paso(5, "Busca la acción Abrir captura rápida de Lana y agrégala.")
                paso(6, "Cada vez que pagues con el iPhone se te abre Lana en la captura.")
            }

            Section("Opción 5 · Widget") {
                Text("Mantén presionada la pantalla de inicio → Editar → Agregar widget → Lana. El widget de gasto trae botón para registrar.")
                    .font(.subheadline)
            }

            Section {
                Text("Si Siri no te ofrece las frases recién instalada, abre Lana una vez y espera un minuto: iOS tarda tantito en indexarlas. También revisa que Siri esté en español.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Registrar más rápido")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func paso(_ n: Int, _ texto: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
            Text(texto).font(.subheadline)
        }
        .padding(.vertical, 2)
    }
}
