import SwiftUI

/// Identidad visual de cada banco/fintech: color de marca y monograma.
///
/// No trae los logos oficiales (son marcas registradas y no se pueden
/// empaquetar así nomás). Si quieres los reales, mete el PNG al catálogo de
/// assets con el nombre que dice `asset` y la app lo usa solo.
struct Marca {
    let colorHex: String
    let monograma: String
    var simbolo: String? = nil
    var asset: String

    init(_ colorHex: String, _ monograma: String, simbolo: String? = nil, asset: String) {
        self.colorHex = colorHex
        self.monograma = monograma
        self.simbolo = simbolo
        self.asset = asset
    }
}

enum Marcas {
    /// Colores tomados de la identidad pública de cada marca.
    private static let tabla: [(clave: String, marca: Marca)] = [
        ("bbva",          Marca("#004481", "BBVA", asset: "logo-bbva")),
        ("nu",            Marca("#820AD1", "nu",   asset: "logo-nu")),
        ("mercado",       Marca("#00A1EA", "MP",   asset: "logo-mercadopago")),
        ("revolut",       Marca("#191C1F", "R",    asset: "logo-revolut")),
        ("didi",          Marca("#FF7D41", "DiDi", asset: "logo-didi")),
        ("plata",         Marca("#6E7178", "P",    asset: "logo-plata")),
        ("santander",     Marca("#EC0000", "S",    asset: "logo-santander")),
        ("banorte",       Marca("#EB0029", "B",    asset: "logo-banorte")),
        ("banamex",       Marca("#056DAE", "C",    asset: "logo-banamex")),
        ("citi",          Marca("#056DAE", "C",    asset: "logo-banamex")),
        ("hsbc",          Marca("#DB0011", "H",    asset: "logo-hsbc")),
        ("scotia",        Marca("#EC111A", "S",    asset: "logo-scotiabank")),
        ("hey",           Marca("#00C08B", "hey",  asset: "logo-hey")),
        ("klar",          Marca("#2B2BFF", "K",    asset: "logo-klar")),
        ("stori",         Marca("#FF4E4E", "S",    asset: "logo-stori")),
        ("rappi",         Marca("#FF441F", "R",    asset: "logo-rappi")),
        ("spin",          Marca("#EE1C25", "S",    asset: "logo-spin")),
        ("oxxo",          Marca("#EE1C25", "O",    asset: "logo-oxxo")),
        ("efectivo",      Marca("#30D158", "$", simbolo: "banknote.fill", asset: "logo-efectivo")),
        ("cetes",         Marca("#9B1B30", "C",    asset: "logo-cetes")),
        ("gbm",           Marca("#111111", "GBM",  asset: "logo-gbm")),
        ("kuspit",        Marca("#00A99D", "K",    asset: "logo-kuspit")),
        ("binance",       Marca("#F0B90B", "B",    asset: "logo-binance")),
        ("bitso",         Marca("#00B5B5", "b",    asset: "logo-bitso"))
    ]

    static func para(_ texto: String) -> Marca? {
        let limpio = texto.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        return tabla.first { limpio.contains($0.clave) }?.marca
    }

    /// Color de marca si la reconocemos; si no, el que traiga la cuenta.
    static func color(para nombre: String, institucion: String = "", respaldo: String) -> String {
        para(nombre)?.colorHex ?? para(institucion)?.colorHex ?? respaldo
    }
}

/// Cuadrito con el logo (o el monograma) de la cuenta.
struct LogoCuenta: View {
    let nombre: String
    var institucion: String = ""
    var respaldoColor: String = "#8E8E93"
    var simboloTipo: String? = nil
    var lado: CGFloat = 38

    private var marca: Marca? { Marcas.para(nombre) ?? Marcas.para(institucion) }

    var body: some View {
        let color = Color(hex: marca?.colorHex ?? respaldoColor)
        RoundedRectangle(cornerRadius: lado * 0.26, style: .continuous)
            .fill(color.gradient)
            .frame(width: lado, height: lado)
            .overlay { contenido }
            .overlay {
                RoundedRectangle(cornerRadius: lado * 0.26, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            }
    }

    @ViewBuilder
    private var contenido: some View {
        if let asset = marca?.asset, UIImage(named: asset) != nil {
            Image(asset)
                .resizable()
                .scaledToFit()
                .padding(lado * 0.18)
        } else if let simbolo = marca?.simbolo {
            Image(systemName: simbolo)
                .font(.system(size: lado * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        } else if let texto = marca?.monograma {
            Text(texto)
                .font(.system(size: tamañoTexto(texto), weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.horizontal, 3)
        } else if let simbolo = simboloTipo {
            Image(systemName: simbolo)
                .font(.system(size: lado * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        } else {
            Text(String(nombre.prefix(1)).uppercased())
                .font(.system(size: lado * 0.46, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private func tamañoTexto(_ texto: String) -> CGFloat {
        switch texto.count {
        case 1: lado * 0.46
        case 2: lado * 0.36
        case 3: lado * 0.28
        default: lado * 0.24
        }
    }
}
