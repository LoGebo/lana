import Foundation

/// Adivina la categoría a partir de dónde gastaste.
///
/// Sirve para que Siri y la captura rápida no te pregunten lo obvio:
/// si dices "OXXO" ya sabe que va en Antojos.
enum Adivinador {

    /// Pista → nombre de la categoría. El orden importa: gana la primera.
    private static let pistas: [(pista: String, categoria: String)] = [
        // Antojos
        ("oxxo", "Antojos / OXXO"), ("7 eleven", "Antojos / OXXO"), ("7eleven", "Antojos / OXXO"),
        ("seven", "Antojos / OXXO"), ("circle k", "Antojos / OXXO"), ("tienda", "Antojos / OXXO"),
        ("chelas", "Antojos / OXXO"), ("cerveza", "Antojos / OXXO"),

        // Transporte
        ("uber", "Transporte"), ("didi", "Transporte"), ("cabify", "Transporte"),
        ("taxi", "Transporte"), ("gasolina", "Transporte"), ("pemex", "Transporte"),
        ("metro", "Transporte"), ("camion", "Transporte"), ("estacionamiento", "Transporte"),
        ("caseta", "Transporte"), ("verificacion", "Transporte"),

        // Comida
        ("rappi", "Comida fuera"), ("didi food", "Comida fuera"), ("uber eats", "Comida fuera"),
        ("starbucks", "Comida fuera"), ("cafe", "Comida fuera"), ("tacos", "Comida fuera"),
        ("taqueria", "Comida fuera"), ("restaurante", "Comida fuera"), ("sushi", "Comida fuera"),
        ("pizza", "Comida fuera"), ("mcdonald", "Comida fuera"), ("burger", "Comida fuera"),
        ("kfc", "Comida fuera"), ("wings", "Comida fuera"), ("comida", "Comida fuera"),
        ("desayuno", "Comida fuera"), ("cena", "Comida fuera"),

        // Súper
        ("walmart", "Súper"), ("chedraui", "Súper"), ("soriana", "Súper"), ("costco", "Súper"),
        ("bodega", "Súper"), ("aurrera", "Súper"), ("heb", "Súper"), ("sams", "Súper"),
        ("mercado", "Súper"), ("super", "Súper"), ("despensa", "Súper"), ("fruteria", "Súper"),

        // Suscripciones
        ("netflix", "Suscripciones"), ("spotify", "Suscripciones"), ("hbo", "Suscripciones"),
        ("disney", "Suscripciones"), ("icloud", "Suscripciones"), ("chatgpt", "Suscripciones"),
        ("youtube", "Suscripciones"), ("prime", "Suscripciones"), ("apple one", "Suscripciones"),
        ("suscripcion", "Suscripciones"),

        // Gym y box
        ("smart fit", "Gym"), ("smartfit", "Gym"), ("gimnasio", "Gym"), ("gym", "Gym"),
        ("proteina", "Gym"), ("creatina", "Gym"), ("suplemento", "Gym"),
        ("box", "Box"), ("boxeo", "Box"), ("guantes", "Box"), ("vendas", "Box"),

        // Novia
        ("novia", "Novia"), ("flores", "Novia"), ("ramo", "Novia"), ("aniversario", "Novia"),

        // Compras
        ("mercado libre", "Compras"), ("mercadolibre", "Compras"), ("meli", "Compras"),
        ("amazon", "Compras"), ("shein", "Compras"), ("temu", "Compras"),
        ("liverpool", "Compras"), ("coppel", "Compras"), ("aliexpress", "Compras"),

        // Salud
        ("farmacia", "Salud"), ("similares", "Salud"), ("doctor", "Salud"), ("dentista", "Salud"),
        ("consulta", "Salud"), ("medicina", "Salud"), ("analisis", "Salud"),

        // Diversión
        ("cinepolis", "Diversión"), ("cinemex", "Diversión"), ("cine", "Diversión"),
        ("concierto", "Diversión"), ("antro", "Diversión"), ("bar", "Diversión"),
        ("boliche", "Diversión"), ("videojuego", "Diversión"), ("steam", "Diversión"),

        // Servicios y casa
        ("cfe", "Servicios"), ("luz", "Servicios"), ("agua", "Servicios"), ("gas", "Servicios"),
        ("telmex", "Servicios"), ("izzi", "Servicios"), ("totalplay", "Servicios"),
        ("internet", "Servicios"), ("telcel", "Servicios"), ("at&t", "Servicios"),
        ("renta", "Casa / Renta"), ("mantenimiento", "Casa / Renta"), ("predial", "Casa / Renta"),

        // Ropa
        ("zara", "Ropa"), ("h&m", "Ropa"), ("nike", "Ropa"), ("adidas", "Ropa"),
        ("pull", "Ropa"), ("bershka", "Ropa"), ("ropa", "Ropa"), ("tenis", "Ropa"),

        // Viajes
        ("volaris", "Viajes"), ("aeromexico", "Viajes"), ("vuelo", "Viajes"), ("avion", "Viajes"),
        ("hotel", "Viajes"), ("airbnb", "Viajes"), ("viaje", "Viajes"),

        // Regalos
        ("regalo", "Regalos"), ("cumpleanos", "Regalos")
    ]

    /// Devuelve el nombre de la categoría que le queda a ese texto, si alguna.
    static func categoria(para texto: String) -> String? {
        let limpio = texto
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_MX"))
            .lowercased()
        guard !limpio.isEmpty else { return nil }
        return pistas.first { limpio.contains($0.pista) }?.categoria
    }

    /// Busca la categoría en la lista real: primero por nombre, luego adivinando.
    static func buscar(_ texto: String, en categorias: [Categoria]) -> Categoria? {
        let limpio = texto
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_MX"))
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
        guard !limpio.isEmpty else { return nil }

        func normaliza(_ s: String) -> String {
            s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_MX")).lowercased()
        }

        // Coincidencia exacta con el nombre de una categoría.
        if let exacta = categorias.first(where: { normaliza($0.nombre) == limpio }) {
            return exacta
        }
        // El texto menciona el nombre de una categoría ("gasto de novia").
        if let mencionada = categorias.first(where: { limpio.contains(normaliza($0.nombre)) }) {
            return mencionada
        }
        // Adivinar por comercio.
        if let adivinada = categoria(para: limpio) {
            return categorias.first { normaliza($0.nombre) == normaliza(adivinada) }
        }
        return nil
    }
}
