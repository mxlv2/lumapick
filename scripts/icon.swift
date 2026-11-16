import AppKit
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for size in [16,32,128,256,512] {
 for scale in [1,2] {
  let n = size * scale
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  let bounds = NSRect(x:0,y:0,width:n,height:n)
  let inset = CGFloat(n) * 0.07
  let tile = NSBezierPath(roundedRect: bounds.insetBy(dx:inset,dy:inset), xRadius:CGFloat(n)*0.2,yRadius:CGFloat(n)*0.2)
  NSGradient(starting: NSColor(calibratedRed:0.18,green:0.62,blue:0.76,alpha:1), ending:NSColor(calibratedRed:0.08,green:0.27,blue:0.49,alpha:1))!.draw(in:tile, angle:80)
  let card = NSRect(x:CGFloat(n)*0.22,y:CGFloat(n)*0.25,width:CGFloat(n)*0.56,height:CGFloat(n)*0.5)
  NSColor.white.withAlphaComponent(0.94).setFill(); NSBezierPath(roundedRect:card,xRadius:CGFloat(n)*0.055,yRadius:CGFloat(n)*0.055).fill()
  NSColor(calibratedRed:0.22,green:0.53,blue:0.62,alpha:1).setFill()
  let mountain=NSBezierPath(); mountain.move(to:NSPoint(x:CGFloat(n)*0.28,y:CGFloat(n)*0.32)); mountain.line(to:NSPoint(x:CGFloat(n)*0.43,y:CGFloat(n)*0.56)); mountain.line(to:NSPoint(x:CGFloat(n)*0.56,y:CGFloat(n)*0.40)); mountain.line(to:NSPoint(x:CGFloat(n)*0.64,y:CGFloat(n)*0.51)); mountain.line(to:NSPoint(x:CGFloat(n)*0.73,y:CGFloat(n)*0.32)); mountain.close(); mountain.fill()
  NSColor.systemGreen.setFill(); NSBezierPath(ovalIn:NSRect(x:CGFloat(n)*0.60,y:CGFloat(n)*0.16,width:CGFloat(n)*0.25,height:CGFloat(n)*0.25)).fill()
  NSColor.white.setStroke(); let check=NSBezierPath(); check.lineWidth=CGFloat(n)*0.025; check.lineCapStyle = .round; check.move(to:NSPoint(x:CGFloat(n)*0.66,y:CGFloat(n)*0.28)); check.line(to:NSPoint(x:CGFloat(n)*0.71,y:CGFloat(n)*0.23)); check.line(to:NSPoint(x:CGFloat(n)*0.79,y:CGFloat(n)*0.33)); check.stroke()
  NSGraphicsContext.restoreGraphicsState()
  let filename="icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
  try rep.representation(using:.png,properties:[:])!.write(to:dir.appendingPathComponent(filename))
 }
}
