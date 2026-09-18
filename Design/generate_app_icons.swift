// Vom Repository-Stamm ausführen: swift Design/generate_app_icons.swift
// Erzeugt die drei 1024er-App-Icons (Light/Dark/Tinted) samt Contents.json und die
// SVG-Vorschauen in Design/app_icon. Reines CoreGraphics, keine Abhängigkeiten.
// Farben pro Erscheinung stehen in `palettes` — dort ansetzen, wenn das Icon vom
// Aqua-Blau ins App-Grün (Minze & Honig) wechseln soll.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let fm = FileManager.default
let glass = "M 32 27 L 76 27 C 78 27 79 29 78.7 31 L 73 74 C 72.4 78.5 69.8 81 65.5 81 L 42.5 81 C 38.2 81 35.6 78.5 35 74 L 29.3 31 C 29 29 30 27 32 27 Z M 34.3 32 L 36.8 53 C 43 49 47 52 54 54.5 C 61 57 66 50 71.2 53 L 73.7 32 Z"
let drop = "M 54 35 C 51.8 38.8 49 42 49 45 C 49 48 51 50 54 50 C 57 50 59 48 59 45 C 59 42 56.2 38.8 54 35 Z"
let silhouette = glass + " " + drop
func path(_ data: String) -> CGPath {
    let t = data.split(separator: " ").map(String.init)
    let p = CGMutablePath(); var i = 0
    func n() -> CGFloat { defer { i += 1 }; return CGFloat(Double(t[i])!) }
    while i < t.count {
        let op = t[i]; i += 1
        switch op {
        case "M": p.move(to: CGPoint(x: n(), y: n()))
        case "L": p.addLine(to: CGPoint(x: n(), y: n()))
        case "C":
            let a = CGPoint(x: n(), y: n()), b = CGPoint(x: n(), y: n()), c = CGPoint(x: n(), y: n())
            p.addCurve(to: c, control1: a, control2: b)
        case "Z": p.closeSubpath()
        default: fatalError("Unsupported path command")
        }
    }
    return p
}
func color(_ hex: String) -> CGColor {
    let v = UInt32(hex, radix: 16)!
    return CGColor(red: CGFloat((v >> 16) & 255)/255, green: CGFloat((v >> 8) & 255)/255, blue: CGFloat(v & 255)/255, alpha: 1)
}
func write(_ file: String, _ text: String) throws {
    try fm.createDirectory(atPath: (file as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try text.write(toFile: file, atomically: true, encoding: .utf8)
}
let palettes = ["light": ["68E4EA", "0088C7", "FFFFFF"], "dark": ["075366", "020C12", "ADF6F4"], "tinted": ["303033", "080809", "FFFFFF"]]
func render(_ file: String, size: Int, appearance: String, scale: CGFloat, round: Bool = false) throws {
    try fm.createDirectory(atPath: (file as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: (round ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast).rawValue)!
    ctx.scaleBy(x: CGFloat(size)/108, y: CGFloat(size)/108)
    ctx.translateBy(x: 0, y: 108); ctx.scaleBy(x: 1, y: -1)
    if round { ctx.addEllipse(in: CGRect(x: 0, y: 0, width: 108, height: 108)); ctx.clip() }
    let colors = palettes[appearance]!
    let gradient = CGGradient(colorsSpace: cs, colors: [color(colors[0]), color(colors[1])] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 54, y: 0), end: CGPoint(x: 54, y: 108), options: [])
    ctx.translateBy(x: 54, y: 54); ctx.scaleBy(x: scale, y: scale); ctx.translateBy(x: -54, y: -54)
    ctx.addPath(path(silhouette)); ctx.setFillColor(color(colors[2])); ctx.drawPath(using: .eoFill)
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: file) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("PNG export failed") }
}
let iconDir = "TrinkTracker/Assets.xcassets/AppIcon.appiconset"
let svgDir = "Design/app_icon"
var images: [[String: Any]] = []
for variant in ["light", "dark", "tinted"] {
    let filename = "Icon-\(variant)-1024.png"
    try render(iconDir + "/" + filename, size: 1024, appearance: variant, scale: 1.23)
    var entry: [String: Any] = ["filename": filename, "idiom": "universal", "platform": "ios", "size": "1024x1024"]
    if variant != "light" { entry["appearances"] = [["appearance": "luminosity", "value": variant]] }
    images.append(entry)
    let c = palettes[variant]!
    try write("\(svgDir)/\(variant).svg", """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108">
      <defs><linearGradient id="background" x2="0" y2="1"><stop stop-color="#\(c[0])"/><stop offset="1" stop-color="#\(c[1])"/></linearGradient></defs>
      <path fill="url(#background)" d="M0 0H108V108H0Z"/>
      <path fill="#\(c[2])" fill-rule="evenodd" transform="translate(54 54) scale(1.23) translate(-54 -54)" d="\(silhouette)"/>
    </svg>
    """)
}
let catalog: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys])
    .write(to: URL(fileURLWithPath: iconDir + "/Contents.json"))
try write("\(svgDir)/foreground.svg", """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108">
  <path fill="white" fill-rule="evenodd" transform="translate(54 54) scale(.9) translate(-54 -54)" d="\(silhouette)"/>
</svg>
""")
print("App-Icons (Light/Dark/Tinted), Contents.json und SVG-Vorschauen erzeugt.")
