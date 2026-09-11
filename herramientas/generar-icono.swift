#!/usr/bin/env swift
// Genera un ícono neutro para la app si no hay uno.
// El ícono real no va en el repo: es personal. Corre esto tras clonar:
//     swift herramientas/generar-icono.swift

import AppKit

let destino = "Lana/Assets.xcassets/AppIcon.appiconset/icono.png"

if FileManager.default.fileExists(atPath: destino) {
    print("Ya hay un ícono en \(destino); no lo toco.")
    exit(0)
}

let lado = 1024

// Sin canal alfa: los iconos de iOS no lo admiten.
guard let lienzo = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: lado, pixelsHigh: lado,
    bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: lienzo)

let marco = NSRect(x: 0, y: 0, width: lado, height: lado)
NSGradient(colors: [
    NSColor(srgbRed: 0.22, green: 0.85, blue: 0.47, alpha: 1),
    NSColor(srgbRed: 0.03, green: 0.48, blue: 0.30, alpha: 1)
])?.draw(in: marco, angle: -90)

let simbolo = "$" as NSString
let atributos: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 640, weight: .heavy),
    .foregroundColor: NSColor.white
]
let medida = simbolo.size(withAttributes: atributos)
simbolo.draw(
    at: NSPoint(x: (CGFloat(lado) - medida.width) / 2,
                y: (CGFloat(lado) - medida.height) / 2),
    withAttributes: atributos
)

NSGraphicsContext.restoreGraphicsState()

guard let png = lienzo.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: destino))
print("Ícono generado en \(destino)")
