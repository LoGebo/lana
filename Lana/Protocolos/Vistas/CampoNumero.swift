import SwiftUI

/// Campo numérico simple: vacío cuando vale 0, sin signo de pesos.
struct CampoNumero: View {
    var marcador: String = "0"
    @Binding var valor: Double
    var ancho: CGFloat = 64
    var alineacion: TextAlignment = .center
    var etiqueta: String = ""

    @State private var texto = ""
    @FocusState private var enfocado: Bool

    var body: some View {
        TextField(marcador, text: $texto)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(alineacion)
            .frame(width: ancho)
            .focused($enfocado)
            .accessibilityLabel(etiqueta.isEmpty ? marcador : etiqueta)
            .onAppear { texto = valor == 0 ? "" : numeroLimpio(valor) }
            .onChange(of: texto) { _, t in
                valor = Double(t.replacingOccurrences(of: ",", with: ".")) ?? 0
            }
            .onChange(of: enfocado) { _, ahora in
                // Como Hevy: al tocar un valor precargado queda seleccionado, y lo que escribas lo reemplaza.
                if ahora {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
                    }
                }
            }
            .onChange(of: valor) { _, nuevo in
                if !enfocado { texto = nuevo == 0 ? "" : numeroLimpio(nuevo) }
            }
            .toolbar {
                if enfocado {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Listo") { enfocado = false }.fontWeight(.semibold)
                    }
                }
            }
    }
}
