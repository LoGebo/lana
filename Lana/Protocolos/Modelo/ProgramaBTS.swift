// STUB: el contenido del programa de Jeff Nippard (producto de pago) no se publica en este repo.
// Pon aquí tu copia (fases + catálogo con videos) y márcala: git update-index --skip-worktree <este archivo>
import Foundation

struct ProgEj { let n: String; let s: Int; let r: String; let e: String; let l: String; let d: Int; let t: String; let w: String }
struct ProgFase { let titulo: String; let desde: Int; let hasta: Int; let dias: [(String, [ProgEj])] }
struct ProgInfo { let url: String; let nota: String; let alt: [(String, String)] }

enum Programa {
    static let fases: [ProgFase] = []
    static let catalogo: [String: ProgInfo] = [:]
}
