import SwiftUI

struct Anillo: View {
    let progreso: Double, color: Color, grosor: CGFloat
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: grosor)
            Circle().trim(from: 0, to: min(max(progreso, 0), 1)).stroke(color, style: StrokeStyle(lineWidth: grosor, lineCap: .round)).rotationEffect(.degrees(-90))
        }
    }
}

func fraccion(_ v: Double, _ meta: Double) -> Double { meta > 0 ? v / meta : 0 }

struct HoyView: View {
    @EnvironmentObject var m: ModeloWatch

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                let r = m.resumen
                ZStack {
                    Anillo(progreso: fraccion(r.kcal, r.kcalMeta), color: .green, grosor: 9)
                    Anillo(progreso: fraccion(r.proteina, r.proteinaMeta), color: .orange, grosor: 9).padding(11)
                    VStack(spacing: 0) {
                        Text(r.kcalMeta > 0 ? "\(Int(max(r.kcalMeta - r.kcal, 0)))" : "\(Int(r.kcal))").font(.title3.bold().monospacedDigit())
                        Text(r.kcalMeta > 0 ? "kcal restan" : "kcal").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 96, height: 96)
                HStack {
                    Label("\(Int(r.kcal))", systemImage: "flame.fill").foregroundStyle(.green)
                    Spacer()
                    Label("\(Int(r.proteina)) g", systemImage: "bolt.fill").foregroundStyle(.orange)
                }.font(.caption2)

                HStack {
                    Image(systemName: "drop.fill").foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(Int(m.aguaMostrada)) ml").font(.caption.bold().monospacedDigit())
                        Text("de \(Int(r.aguaMeta))").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    boton("minus", .gray) { m.deshacerAgua() }.disabled(!m.hayAguaPendiente).accessibilityLabel("Quitar 250 ml")
                    boton("plus", .cyan) { m.enviar(.agua(ml: 250)) }.accessibilityLabel("Agregar 250 ml")
                }
                .padding(8)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))

                fila("dumbbell.fill", .green, r.rutina ?? "Descanso", r.rutina == nil ? "Hoy no toca gym" : "\(r.ejercicios.count) ejercicios")
                fila("moon.zzz.fill", .indigo, m.suenoHoras.map { "\(Int($0)) h \(Int(($0 - floor($0)) * 60)) min" } ?? "Sin datos", "Sueño de anoche")
                if !m.pendientes.isEmpty {
                    Label("\(m.pendientes.count) sin enviar", systemImage: "arrow.triangle.2.circlepath").font(.caption2).foregroundStyle(.yellow)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Hoy")
    }

    private func boton(_ icono: String, _ color: Color, _ accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Image(systemName: icono).font(.footnote.bold()).frame(width: 34, height: 34).background(color.opacity(0.3), in: Circle())
        }.buttonStyle(.plain)
    }

    private func fila(_ icono: String, _ color: Color, _ titulo: String, _ sub: String) -> some View {
        HStack {
            Image(systemName: icono).foregroundStyle(color).frame(width: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(titulo).font(.caption.bold()).lineLimit(1)
                Text(sub).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(8).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct EntrenoView: View {
    @EnvironmentObject var m: ModeloWatch
    @EnvironmentObject var e: EntrenoModelo
    @FocusState private var foco: Campo?
    @State private var terminando = false
    @State private var error = false
    enum Campo { case kg, reps }

    var body: some View {
        Group {
            if !e.activo { inicio } else { sesion }
        }
        .navigationTitle("Gym")
    }

    private var inicio: some View {
        VStack(spacing: 8) {
            Image(systemName: "dumbbell.fill").font(.title2).foregroundStyle(.green)
            Text(m.rutinaHoy ?? "Hoy no toca gym").font(.headline).multilineTextAlignment(.center)
            if m.rutinaHoy != nil {
                Text("\(m.resumen.ejercicios.count) ejercicios").font(.caption).foregroundStyle(.secondary)
                Button("Empezar") { Task { await e.empezar(m.resumen) } }.tint(.green).buttonStyle(.borderedProminent)
            } else {
                Text("Abre Lana en el iPhone para sincronizar").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }

    private var sesion: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let fin = e.finDescanso {
                    VStack(spacing: 2) {
                        Text("Descanso").font(.caption).foregroundStyle(.secondary)
                        Text(fin, style: .timer).font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(.cyan)
                        Button("Saltar") { e.saltarDescanso() }.buttonStyle(.bordered)
                    }
                }
                if let x = e.actual {
                    Text(x.nombre).font(.headline).multilineTextAlignment(.center).lineLimit(2)
                    Text("Serie \(min(e.serieActual, x.series)) de \(x.series) · \(x.reps) reps").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        caja("kg", String(format: "%g", e.kg), .kg)
                            .digitalCrownRotation($e.kg, from: 0, through: 300, by: 2.5, sensitivity: .medium)
                        caja("reps", "\(Int(e.reps))", .reps)
                            .digitalCrownRotation($e.reps, from: 1, through: 50, by: 1, sensitivity: .medium)
                    }
                    Button("Hecha") { error = !e.hecha(m) }.buttonStyle(.borderedProminent).tint(.green)
                    if error { Text("No se pudo guardar").font(.caption2).foregroundStyle(.red) }
                    Button("Siguiente ejercicio") { e.saltarEjercicio() }.font(.caption2).disabled(e.idx + 1 >= e.ejercicios.count)
                }
                HStack {
                    Label(e.fc > 0 ? "\(Int(e.fc))" : "--", systemImage: "heart.fill").foregroundStyle(.red)
                    Spacer()
                    Text("\(e.totalSeries) series").foregroundStyle(.secondary)
                }.font(.caption2)
                Button("Terminar", role: .destructive) { terminando = true }.font(.caption)
            }
        }
        .onAppear { foco = .kg }
        .confirmationDialog("¿Terminar entrenamiento?", isPresented: $terminando) {
            Button("Terminar y guardar en Salud") { Task { await e.terminar() } }
        }
    }

    private func caja(_ t: String, _ v: String, _ c: Campo) -> some View {
        VStack(spacing: 0) {
            Text(v).font(.title3.bold().monospacedDigit())
            Text(t).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 6)
        .background(foco == c ? Color.green.opacity(0.35) : Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
        .focusable().focused($foco, equals: c)
        .onTapGesture { foco = c }
    }
}

struct GastoView: View {
    @EnvironmentObject var m: ModeloWatch
    @State private var monto = 0.0
    @State private var categoria = ""
    @State private var ok = false
    @FocusState private var enfocado: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("$\(Int(monto))").font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .focusable().focused($enfocado)
                    .digitalCrownRotation($monto, from: 0, through: 5000, by: 10, sensitivity: .high)
                Text("Gira la corona").font(.system(size: 10)).foregroundStyle(.secondary)
                if !m.resumen.categorias.isEmpty {
                    Picker("Categoría", selection: $categoria) {
                        Text("Sin categoría").tag("")
                        ForEach(m.resumen.categorias, id: \.self) { Text($0).tag($0) }
                    }
                }
                Button(ok ? "Guardado ✓" : "Guardar gasto") {
                    if m.enviar(.gasto(monto: monto, categoria: categoria.isEmpty ? nil : categoria)) {
                        monto = 0; ok = true
                        Task { try? await Task.sleep(for: .seconds(1.5)); ok = false }
                    }
                }.buttonStyle(.borderedProminent).tint(.green).disabled(monto <= 0)
            }
        }
        .onAppear { enfocado = true }
        .navigationTitle("Gasto")
    }
}

struct PesoView: View {
    @EnvironmentObject var m: ModeloWatch
    @State private var kg = 75.0
    @State private var ok = false
    @FocusState private var enfocado: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text(String(format: "%.1f kg", kg)).font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                .focusable().focused($enfocado)
                .digitalCrownRotation($kg, from: 30, through: 250, by: 0.1, sensitivity: .medium)
            Text("Pésate en ayunas").font(.system(size: 10)).foregroundStyle(.secondary)
            Button(ok ? "Guardado ✓" : "Guardar peso") {
                if m.enviar(.peso(kg: (kg * 10).rounded() / 10)) { ok = true; Task { try? await Task.sleep(for: .seconds(1.5)); ok = false } }
            }.buttonStyle(.borderedProminent).tint(.green)
        }
        .onAppear { enfocado = true; if let p = m.resumen.pesoKg { kg = p } }
        .navigationTitle("Peso")
    }
}
