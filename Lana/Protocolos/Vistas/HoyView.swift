import SwiftUI
import SwiftData

/// Pantalla Hoy: checklist de 1 minuto + cómo dormiste.
struct HoyView: View {
    @Environment(\.modelContext) private var contexto
    @Query private var logs: [HabitoLog]
    @AppStorage(Rampa.llaveSemana) private var semana = 1
    @ObservedObject var salud: SaludService
    @Query private var comidas: [ComidaLog]
    @Query(sort: \NocheSueno.dia, order: .reverse) private var nochesGuardadas: [NocheSueno]
    @AppStorage("protocolos.sueno.meta") private var metaSueno = 8.0
    @AppStorage(LlavesMetas.kcal) private var metaKcal: Double = 0
    @AppStorage(LlavesMetas.proteina) private var metaProteina: Double = 0

    private var hoy: Date { Calendar.current.startOfDay(for: Date()) }
    private var habitosDeHoy: [Habito] { Habito.allCases.filter { $0.aplica(en: Date()) } }
    // ponytail: filtro en memoria; con años de datos, mover a #Predicate por día.
    private var hechos: Set<String> { Set(logs.filter { $0.dia == hoy }.map(\.clave)) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                tarjetaNoche
                tarjetaComida
                tarjetaChecklist
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var tarjetaNoche: some View {
        let paso = Rampa.paso(semana)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Anoche").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            let todas = NocheSueno.mejorPorDia(nochesGuardadas)
            if let n = todas.first {
                Text(minutosTexto(n.minDormido))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text("Puntaje \(AnalisisSueno.puntaje(de: n, entre: todas, metaHoras: metaSueno).total)/100 · eficiencia \(Int((n.eficiencia * 100).rounded())) %")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Dormiste \(n.dormido.formatted(date: .omitted, time: .shortened)) → \(n.despierto.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text(salud.cargando ? "Leyendo Salud…" : "Sin datos de sueño")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Label("Acuéstate a las \(horaTexto(minutos: paso.dormir))", systemImage: "bed.double.fill")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("Semana \(semana)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var tarjetaComida: some View {
        let t = TotalesDia(comidas.filter { $0.dia == hoy })
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Proteína hoy").font(.footnote).foregroundStyle(.secondary)
                Text(metaProteina > 0 ? "\(Int(t.proteina)) / \(Int(metaProteina)) g" : "\(Int(t.proteina)) g")
                    .font(.title3.weight(.bold))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Calorías").font(.footnote).foregroundStyle(.secondary)
                Text(metaKcal > 0 ? "\(Int(t.kcal)) / \(Int(metaKcal))" : "\(Int(t.kcal))")
                    .font(.title3.weight(.bold))
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var tarjetaChecklist: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Checklist").font(.headline)
                Spacer()
                Text("\(hechos.intersection(Set(habitosDeHoy.map(\.rawValue))).count)/\(habitosDeHoy.count)")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
            }
            .padding(.bottom, 6)

            ForEach(habitosDeHoy) { h in
                let hecho = hechos.contains(h.rawValue)
                Button { alternar(h) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: h.icono).frame(width: 26).foregroundStyle(hecho ? .green : .secondary)
                        Text(h.nombre).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: hecho ? "checkmark.circle.fill" : "circle")
                            .font(.title3).foregroundStyle(hecho ? .green : .secondary)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if h != habitosDeHoy.last { Divider() }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func alternar(_ h: Habito) {
        if let existente = logs.first(where: { $0.dia == hoy && $0.clave == h.rawValue }) {
            contexto.delete(existente)
        } else {
            contexto.insert(HabitoLog(dia: hoy, clave: h.rawValue))
        }
        try? contexto.save()
    }
}
