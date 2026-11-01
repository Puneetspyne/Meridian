// Draws the Meridian app icon at 1024x1024. Usage: swift scripts/make-icon.swift out.png
import AppKit
import CoreGraphics

let size = 1024
let s = CGFloat(size)
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    FileHandle.standardError.write(Data("cannot create context\n".utf8)); exit(1)
}
ctx.setAllowsAntialiasing(true)
ctx.interpolationQuality = .high

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat(r)/255, CGFloat(g)/255, CGFloat(b)/255, a])!
}

// macOS icon grid: the artwork sits in an 824 px square centered on the 1024 canvas.
let inset: CGFloat = 100
let body = CGRect(x: inset, y: inset, width: s - 2*inset, height: s - 2*inset)
let side = body.width

// Continuous-corner (squircle) path: superellipse-ish rounded rect built from cubic curves.
func squircle(_ r: CGRect, radius: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let k: CGFloat = 1.28195  // extends the curve like Apple's continuous corners
    let c = min(radius * k, min(r.width, r.height) / 2)
    let minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
    p.move(to: CGPoint(x: minX + c, y: minY))
    p.addLine(to: CGPoint(x: maxX - c, y: minY))
    p.addCurve(to: CGPoint(x: maxX, y: minY + c), control1: CGPoint(x: maxX - c*0.45, y: minY), control2: CGPoint(x: maxX, y: minY + c*0.45))
    p.addLine(to: CGPoint(x: maxX, y: maxY - c))
    p.addCurve(to: CGPoint(x: maxX - c, y: maxY), control1: CGPoint(x: maxX, y: maxY - c*0.45), control2: CGPoint(x: maxX - c*0.45, y: maxY))
    p.addLine(to: CGPoint(x: minX + c, y: maxY))
    p.addCurve(to: CGPoint(x: minX, y: maxY - c), control1: CGPoint(x: minX + c*0.45, y: maxY), control2: CGPoint(x: minX, y: maxY - c*0.45))
    p.addLine(to: CGPoint(x: minX, y: minY + c))
    p.addCurve(to: CGPoint(x: minX + c, y: minY), control1: CGPoint(x: minX, y: minY + c*0.45), control2: CGPoint(x: minX + c*0.45, y: minY))
    p.closeSubpath()
    return p
}
let shape = squircle(body, radius: side * 0.2237)

// Drop shadow under the body.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0, 0, 0, 0.45))
ctx.addPath(shape); ctx.setFillColor(rgb(11, 11, 15)); ctx.fillPath()
ctx.restoreGState()

// Clip to the body for everything else.
ctx.saveGState()
ctx.addPath(shape); ctx.clip()
ctx.setFillColor(rgb(11, 11, 15)); ctx.fill(body)

// Very subtle radial highlight, upper center.
let grad = CGGradient(colorsSpace: cs, colors: [rgb(60, 66, 92, 0.38), rgb(11, 11, 15, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(grad, startCenter: CGPoint(x: body.midX, y: body.maxY - side*0.18), startRadius: 0,
                       endCenter: CGPoint(x: body.midX, y: body.maxY - side*0.18), endRadius: side*0.75, options: [])

let cx = body.midX, cy = body.midY
let ry = side * 0.36       // meridian ellipse vertical radius (a bit taller than wide: great circle seen at an angle)
let rx = side * 0.20
let stroke: CGFloat = 28
let ellipse = CGRect(x: cx - rx, y: cy - ry, width: rx*2, height: ry*2)

// Equator: thin line at 40% white, spans the globe width.
let eqHalf = ry
ctx.setStrokeColor(rgb(255, 255, 255, 0.40))
ctx.setLineWidth(14)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: cx - eqHalf, y: cy)); ctx.addLine(to: CGPoint(x: cx + eqHalf, y: cy)); ctx.strokePath()

// Meridian ellipse with soft glow.
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 42, color: rgb(160, 200, 255, 0.85))
ctx.setStrokeColor(rgb(255, 255, 255, 0.90))
ctx.setLineWidth(stroke)
ctx.strokeEllipse(in: ellipse)
ctx.restoreGState()
ctx.setStrokeColor(rgb(255, 255, 255, 0.90))
ctx.setLineWidth(stroke)
ctx.strokeEllipse(in: ellipse)

// Dot at the top intersection (where the meridian is at its highest point), systemTeal.
let teal = NSColor.systemTeal.usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0.19, green: 0.69, blue: 0.78, alpha: 1)
let tealCG = CGColor(colorSpace: cs, components: [teal.redComponent, teal.greenComponent, teal.blueComponent, 1])!
let dotC = CGPoint(x: cx, y: cy + ry)
let dotR: CGFloat = 40
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 30, color: tealCG)
ctx.setFillColor(tealCG)
ctx.fillEllipse(in: CGRect(x: dotC.x - dotR, y: dotC.y - dotR, width: dotR*2, height: dotR*2))
ctx.restoreGState()
ctx.setFillColor(tealCG)
ctx.fillEllipse(in: CGRect(x: dotC.x - dotR, y: dotC.y - dotR, width: dotR*2, height: dotR*2))

// Hairline inner edge for definition.
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(shape); ctx.setStrokeColor(rgb(255, 255, 255, 0.10)); ctx.setLineWidth(3); ctx.strokePath()
ctx.restoreGState()

guard let img = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: img)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
