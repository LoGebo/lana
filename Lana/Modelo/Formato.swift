import SwiftUI

// MARK: - Colores

extension Color {
    init(hex: String) {
        let limpio = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var valor: UInt64 = 0
        Scanner(string: limpio).scanHexInt64(&valor)
        guard limpio.count == 6 else {
            self.init(white: 0.55)
            return
        }
        self.init(
            red: Double((valor >> 16) & 0xFF) / 255,
            green: Double((valor >> 8) & 0xFF) / 255,
            blue: Double(valor & 0xFF) / 255
        )
    }
}

/// Paleta para categorías y cuentas.
let paletaLana: [String] = [
    "#0A84FF", "#30D158", "#FF9F0A", "#FF375F", "#BF5AF2",
    "#5E5CE6", "#64D2FF", "#FFD60A", "#FF6482", "#40C8E0",
    "#AC8E68", "#8E8E93"
]

// MARK: - Dinero

private let formateadorPesos: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "MXN"
    f.currencySymbol = "$"
    f.locale = Locale(identifier: "es_MX")
    f.maximumFractionDigits = 2
    f.minimumFractionDigits = 2
    return f
}()

private let formateadorPesosEnteros: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "MXN"
    f.currencySymbol = "$"
    f.locale = Locale(identifier: "es_MX")
    f.maximumFractionDigits = 0
    return f
}()

func pesos(_ monto: Double, decimales: Bool = true) -> String {
    let f = decimales ? formateadorPesos : formateadorPesosEnteros
    return f.string(from: NSNumber(value: monto)) ?? "$0"
}

/// Para espacios apretados: $12.4k
func pesosCortos(_ monto: Double) -> String {
    let abs = Swift.abs(monto)
    let signo = monto < 0 ? "-" : ""
    if abs >= 1_000_000 { return String(format: "%@$%.1fM", signo, abs / 1_000_000) }
    if abs >= 10_000 { return String(format: "%@$%.1fk", signo, abs / 1_000) }
    return pesos(monto, decimales: false)
}

func porcentaje(_ valor: Double, decimales: Int = 1) -> String {
    String(format: "%.\(decimales)f%%", valor)
}

// MARK: - Fechas

func fechaCorta(_ fecha: Date) -> String {
    fecha.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "es_MX")))
}

/// "septiembre de 2026" -> "Septiembre de 2026" (sin capitalizar el "de").
private func conMayusculaInicial(_ texto: String) -> String {
    guard let primera = texto.first else { return texto }
    return primera.uppercased() + texto.dropFirst()
}

func encabezadoDia(_ fecha: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(fecha) { return "Hoy" }
    if cal.isDateInYesterday(fecha) { return "Ayer" }
    let texto = fecha.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es_MX")))
    return conMayusculaInicial(texto)
}

func nombreMes(_ fecha: Date) -> String {
    conMayusculaInicial(fecha.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "es_MX"))))
}

// MARK: - Teclado

/// El teclado numérico de iOS no trae tecla de Enter, así que sin esto
/// no hay forma de cerrarlo. Le pone una barra con "Listo" encima.
private struct CierreDeTeclado: ViewModifier {
    @FocusState private var enfocado: Bool

    func body(content: Content) -> some View {
        content
            .focused($enfocado)
            .toolbar {
                if enfocado {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Listo") { enfocado = false }
                            .fontWeight(.semibold)
                    }
                }
            }
    }
}

extension View {
    /// Úsalo en cualquier campo numérico para poder cerrar el teclado.
    func conBotonListo() -> some View {
        modifier(CierreDeTeclado())
    }
}

/// Campo de dinero que no se pelea contigo mientras escribes.
///
/// El truco: mientras tecleas, el texto vive aquí adentro y no toca el modelo.
/// Si guardáramos en cada tecla, SwiftData redibuja la pantalla y te reformatea
/// el número a media escritura. El valor se aplica al salir del campo o al
/// darle "Listo".
struct CampoMonto: View {
    var marcador: String = "0"
    @Binding var valor: Double
    var ancho: CGFloat = 110
    var alineacion: TextAlignment = .trailing

    @State private var texto = ""
    @State private var cargado = false
    @FocusState private var enfocado: Bool

    var body: some View {
        TextField(marcador, text: $texto)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(alineacion)
            .frame(width: ancho)
            .focused($enfocado)
            .onAppear {
                guard !cargado else { return }
                cargado = true
                texto = comoTexto(valor)
            }
            .onChange(of: enfocado) { _, ahora in
                if ahora {
                    // Al entrar, sin formato: es más fácil corregirlo.
                    texto = valor == 0 ? "" : limpio(valor)
                } else {
                    aplicar()
                }
            }
            .onChange(of: valor) { _, nuevo in
                // Si cambia desde otro lado, lo reflejamos (pero no mientras escribes).
                if !enfocado { texto = comoTexto(nuevo) }
            }
            .toolbar {
                if enfocado {
                    ToolbarItemGroup(placement: .keyboard) {
                        Button("Borrar") { texto = "" }
                            .foregroundStyle(.red)
                        Spacer()
                        Button("Listo") { enfocado = false }
                            .fontWeight(.semibold)
                    }
                }
            }
    }

    private func aplicar() {
        let crudo = texto
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
        valor = Double(crudo) ?? 0
        texto = comoTexto(valor)
    }

    private func limpio(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }

    private func comoTexto(_ v: Double) -> String {
        v == 0 ? "" : pesos(v, decimales: false)
    }
}
