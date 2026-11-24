import SwiftUI
import SwiftData

/// Diario de comida estilo MyFitnessPal: calorías restantes, macros, agua y 4 comidas.
struct ComidaView: View {
    @Environment(\.modelContext) private var contexto
    @Query(sort: \ComidaLog.dia) private var logs: [ComidaLog]
    @Query private var aguas: [AguaLog]

    @AppStorage(LlavesMetas.kcal) private var metaKcal: Double = 0
    @AppStorage(LlavesMetas.proteina) private var metaProteina: Double = 0
    @AppStorage(LlavesMetas.carbs) private var metaCarbs: Double = 0
    @AppStorage(LlavesMetas.grasa) private var metaGrasa: Double = 0
    @AppStorage(LlavesMetas.agua) private var metaAgua: Double = 3000

    @State private var dia = Calendar.current.startOfDay(for: Date())
    @State private var añadiendo: TiempoComida?
    @State private var editando: ComidaLog?
    @State private var metas = false

    private var delDia: [ComidaLog] { logs.filter { $0.dia == dia } }
    private var totales: TotalesDia { TotalesDia(delDia) }
    private var mlHoy: Double { aguas.filter { $0.dia == dia }.reduce(0) { $0 + $1.ml } }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                selectorDia
                tarjetaResumen
                tarjetaAgua
                TarjetaPeso()
                ForEach(TiempoComida.allCases) { t in seccion(t) }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .sheet(item: $añadiendo) { t in AgregarAlimentoView(tiempo: t, dia: dia) }
        .sheet(item: $editando) { l in EditarPorcionesView(log: l) }
        .sheet(isPresented: $metas) { MetasView() }
    }

    private var selectorDia: some View {
        HStack {
            Button { mover(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(Calendar.current.isDateInToday(dia) ? "Hoy" : dia.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                .font(.headline)
            Spacer()
            Button { mover(1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.top, 4)
    }

    private func mover(_ d: Int) {
        dia = Calendar.current.date(byAdding: .day, value: d, to: dia) ?? dia
    }

    private var tarjetaResumen: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(metaKcal > 0 ? "Calorías restantes" : "Calorías").font(.footnote).foregroundStyle(.secondary)
                    Text(metaKcal > 0 ? "\(Int(metaKcal - totales.kcal))" : "\(Int(totales.kcal))")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(metaKcal > 0 && totales.kcal > metaKcal ? .red : .primary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Button { metas = true } label: { Label("Metas", systemImage: "target").font(.subheadline) }
                    Button { DietaMeta.cargar(dia: dia, contexto) } label: { Label("Menú meta", systemImage: "fork.knife").font(.subheadline) }
                        .accessibilityLabel("Cargar menú meta del día")
                }
            }
            if metaKcal > 0 {
                Text("\(Int(metaKcal)) meta − \(Int(totales.kcal)) comidas")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Define tus metas con tu peso, estatura y edad.")
                    .font(.caption).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            barra("Proteína", totales.proteina, metaProteina, .red)
            barra("Carbohidratos", totales.carbs, metaCarbs, .blue)
            barra("Grasa", totales.grasa, metaGrasa, .orange)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func barra(_ nombre: String, _ valor: Double, _ meta: Double, _ color: Color) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(nombre).font(.subheadline)
                Spacer()
                Text(meta > 0 ? "\(Int(valor.rounded())) / \(Int(meta)) g" : "\(Int(valor.rounded())) g")
                    .font(.subheadline.weight(.semibold))
            }
            ProgressView(value: meta > 0 ? min(valor, meta) : 0, total: max(meta, 1)).tint(color)   // sin meta, barra vacía
        }
    }

    private var tarjetaAgua: some View {
        HStack {
            Image(systemName: "drop.fill").foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 1) {
                Text("Agua").font(.subheadline.weight(.medium))
                Text("\(Int(mlHoy)) / \(Int(metaAgua)) ml").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("−250") { sumarAgua(-250) }.buttonStyle(.bordered).disabled(mlHoy <= 0)
            Button("+250") { sumarAgua(250) }.buttonStyle(.borderedProminent).tint(.cyan)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .contextMenu {
            Button("Poner agua en 0", systemImage: "arrow.counterclockwise", role: .destructive) {
                aguas.filter { $0.dia == dia }.forEach(contexto.delete); try? contexto.save()
            }
        }
    }

    private func sumarAgua(_ ml: Double) {
        contexto.insert(AguaLog(dia: dia, ml: max(ml, -mlHoy)))   // nunca baja de 0
        try? contexto.save()
    }

    private func seccion(_ t: TiempoComida) -> some View {
        let items = delDia.filter { $0.tiempo == t }
        let kcal = items.reduce(0) { $0 + $1.kcalTotal }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(t.nombre, systemImage: t.icono).font(.headline)
                Spacer()
                Text("\(Int(kcal)) kcal").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(items) { l in
                Button { editando = l } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l.nombre).font(.subheadline).foregroundStyle(.primary)
                            Text("\(numeroLimpio(l.porciones)) × \(l.porcionTexto) · P \(Int(l.proteinaTotal.rounded())) C \(Int(l.carbsTotal.rounded())) G \(Int(l.grasaTotal.rounded()))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(l.kcalTotal))").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Borrar", systemImage: "trash", role: .destructive) { contexto.delete(l); try? contexto.save() }
                }
                Divider()
            }
            Button { añadiendo = t } label: {
                Label("Agregar alimento", systemImage: "plus.circle.fill").font(.subheadline.weight(.semibold))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}
