# Lana

App de finanzas personales para iPhone. SwiftUI + SwiftData, 100% local, sin backend ni cuentas.

## Abrir el proyecto

El `.xcodeproj` no está en el repo (lo genera XcodeGen y lleva el Team ID de quien compila). Tras clonar:

```bash
brew install xcodegen                      # una sola vez
swift herramientas/generar-icono.swift     # ícono neutro, el real no se versiona
xcodegen generate                          # crea Lana.xcodeproj
open Lana.xcodeproj
```

Vuelve a correr `xcodegen generate` cada vez que agregues un archivo nuevo o toques `project.yml`.

Requiere Xcode 26+ e iOS 18+ en el iPhone.

## Instalarla en tu iPhone

1. Conecta el iPhone por cable.
2. En Xcode: target **Lana** → **Signing & Capabilities** → escoge tu equipo de Apple Developer.
3. Cambia el bundle id si `com.geboou.lana` ya está tomado.
4. Selecciona tu iPhone en la barra superior y dale ▶.

Con cuenta de Apple Developer de paga la app te dura **1 año** instalada (con cuenta gratis caduca cada 7 días).
Si quieres instalarla sin cable, súbela a **TestFlight** y se te actualiza sola.

## Widgets

Mantén presionada la pantalla de inicio → **Editar** → **Agregar widget** → busca **Lana**:

- **Gasto del mes** (chico, mediano y de pantalla bloqueada): cuánto llevas gastado, en qué, y botón **Registrar** que abre la captura de un tap.
- **Mis inversiones**: cuánto tienes invertido y cuánto te genera al mes.

La app y el widget comparten la base por App Group (`group.com.geboou.lana`).

## Rendimientos

Cada cuenta con tasa va sumando su rendimiento **día con día**, con interés compuesto diario, igual que Nu, Mercado Pago o DiDi. Por eso:

- No registres los intereses como ingreso: ya están contados.
- Si tu banco marca otro número, corrige el saldo en la cuenta; ahí el rendimiento vuelve a contar desde ese día.
- La pantalla de Inversiones muestra lo que llevas generado desde que pusiste cada saldo.

## Qué hace

- **Resumen**: gasto del mes, comparación contra el mes pasado, dona por categoría, gasto día por día, dónde más dejas la lana, presupuestos.
- **Movimientos**: todo el historial agrupado por día, búsqueda y filtros por categoría/cuenta.
- **Cuentas**: saldo real de cada cuenta (débito, crédito, efectivo, inversión) y patrimonio total.
- **Inversiones**: cuánto tienes en cada una, su tasa anual, cuánto genera al día/mes/año, tasa promedio ponderada y proyección a 1/3/5 años con interés compuesto.
- **Suscripciones**: cuánto se te va cada mes, próximos cobros, y "ya me lo cobraron" genera el gasto solo.
- **Ajustes**: categorías con presupuesto, exportar CSV, guía de Apple Pay.

## Registrar rápido

iOS no deja que ninguna app lea las compras de Wallet ni las notificaciones del banco. Las cinco vías que sí existen (todas documentadas dentro de la app, en `Ajustes → Registrar más rápido`):

1. **Siri** — la frase **debe** llevar la palabra "Lana": así enruta iOS. `"Oye Siri, registra un gasto de novia en Lana"`. Si dices la categoría, solo te pregunta el monto.
2. **Tocar atrás** — Ajustes → Accesibilidad → Tocar → Tocar atrás → doble toque → un atajo que llame a *Abrir captura rápida*.
3. **Centro de Control / pantalla bloqueada** — control `Registrar gasto` (ControlWidget, iOS 18).
4. **Automatización de Wallet** — Atajos → Automatización → Transacción → *Abrir captura rápida*.
5. **Widget** con botón de registro.

El idioma base del proyecto es **español** (`developmentLanguage: es` en project.yml). Es obligatorio: con el idioma base en inglés, Siri en español no ofrece las frases de App Shortcuts.

Las categorías se deducen del comercio (`Lana/Modelo/Adivinador.swift`): OXXO → Antojos, Uber → Transporte, Mercado Libre → Compras, etc. Funciona igual desde Siri y al escribir el comercio en la captura.

## Quincena automática

`Lana/Modelo/Nomina.swift`. Se prende desde la pestaña Presupuesto. El 15 y el 30 de cada mes (o el último día si el mes es más corto) registra un ingreso por la mitad del ingreso mensual en la cuenta elegida, con categoría Sueldo.

- Se revisa al abrir la app y al volverla a primer plano; si no abriste la app el día 15, el movimiento se crea con su fecha correcta.
- Es idempotente: reconoce sus propios depósitos por la nota `Depósito automático de quincena` y no duplica.
- Al prenderla, `desde` se fija a hoy, así que no rellena quincenas anteriores. El relleno máximo hacia atrás es de 3 meses.

## Campos de dinero

Usa `CampoMonto` (en `Formato.swift`), no `TextField(value:format:)`. Guardar en cada tecla hace que SwiftData redibuje y reformatee el número a media escritura. `CampoMonto` mantiene el texto en estado local y aplica el valor al salir del campo, y trae barra con **Borrar** y **Listo** porque el teclado decimal de iOS no tiene tecla de Enter.

## Ícono

`Lana/Assets.xcassets/AppIcon.appiconset/icono.png`, 1024×1024 **sin canal alfa**. No se versiona: pon el que quieras con ese nombre y tamaño, o corre `swift herramientas/generar-icono.swift` para uno neutro.

## Datos de ejemplo

Para ver la app llena sin capturar nada: en Xcode, Edit Scheme → Run → Arguments → Environment Variables → `LANA_DEMO = 1`. Solo siembra si no hay movimientos.

## Dónde está la lógica

- `Lana/Modelo/Modelos.swift` — Cuenta, Movimiento, Categoria, Suscripcion (SwiftData).
- `Lana/Modelo/Finanzas.swift` — todos los cálculos (saldos, patrimonio, rendimientos, proyecciones).
- `Lana/Modelo/Formato.swift` — pesos mexicanos, fechas, paleta de colores.
- `Lana/Intents/Atajos.swift` — App Intents para Siri y Atajos.
