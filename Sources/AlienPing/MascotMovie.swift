import AppKit
import AVFoundation
import CoreVideo
import ImageIO
import UniformTypeIdentifiers
import AlienCore

/// Offline renderer: draws cached assets into pixel buffers. Never captures a display/window.
enum MascotMovie {
    static func renderAll(to directory:URL) throws {
        guard SpriteLibrary.shared.failure == nil else { throw NSError(domain:"MascotMovie",code:1,userInfo:[NSLocalizedDescriptionKey:SpriteLibrary.shared.failure ?? "Sprites unavailable"]) }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let loads=SpriteLibrary.shared.sheetLoads
        var report:[[String:Any]]=[]
        for character in SpriteLibrary.shared.characters {
            let url=directory.appendingPathComponent(character.name+".mov")
            try render(character,to:url)
            let bytes=(try FileManager.default.attributesOfItem(atPath:url.path)[.size] as? NSNumber)?.intValue ?? 0
            report.append(["id":character.id,"movie":url.lastPathComponent,"durationSeconds":4.8,"videoFPS":30,"videoFrames":144,"bytes":bytes,"animations":character.animations.mapValues { ["uniqueFrames":$0.frameCount,"timelineSteps":$0.sequence.count,"fps":$0.fps] }])
            print("Rendered \(character.name): 144 frames, 30 fps, 4.8 seconds, \(bytes) bytes")
        }
        guard loads == SpriteLibrary.shared.sheetLoads else { throw NSError(domain:"MascotMovie",code:2,userInfo:[NSLocalizedDescriptionKey:"Unexpected repeated sprite loading"]) }
        let data=try JSONSerialization.data(withJSONObject:["screenCapture":false,"sheetLoads":loads,"characters":report],options:[.prettyPrinted,.sortedKeys])
        try data.write(to:directory.appendingPathComponent("render-report.json"),options:.atomic)
    }
    private static func render(_ character:MascotSpec,to url:URL) throws {
        let width=720,height=420,fps:Int32=30
        if FileManager.default.fileExists(atPath:url.path) { try FileManager.default.removeItem(at:url) }
        let writer=try AVAssetWriter(outputURL:url,fileType:.mov)
        let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.proRes4444,AVVideoWidthKey:width,AVVideoHeightKey:height])
        input.expectsMediaDataInRealTime=false
        let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String:width,kCVPixelBufferHeightKey as String:height,kCVPixelBufferCGImageCompatibilityKey as String:true,kCVPixelBufferCGBitmapContextCompatibilityKey as String:true])
        guard writer.canAdd(input) else { throw NSError(domain:"MascotMovie",code:3,userInfo:[NSLocalizedDescriptionKey:"ProRes 4444 encoder unavailable"]) }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? NSError(domain:"MascotMovie",code:4) }
        writer.startSession(atSourceTime:.zero)
        let bounds=CGRect(x:0,y:0,width:width,height:height),anchor=CGPoint(x:350,y:210)
        let seed:UInt64=character.id == "terminal" ? 125 : 99
        let initial=MascotFlight(bounds:bounds,anchor:anchor,seed:seed)
        let flight=MascotFlight(bounds:bounds,anchor:anchor,seed:seed,hold:4.8-initial.entrance-0.8)
        for frame in 0..<144 {
            let deadline=Date().addingTimeInterval(10)
            while !input.isReadyForMoreMediaData && writer.status == .writing && Date()<deadline { Thread.sleep(forTimeInterval:0.002) }
            guard input.isReadyForMoreMediaData,let pool=adaptor.pixelBufferPool else { throw writer.error ?? NSError(domain:"MascotMovie",code:5) }
            var optional:CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil,pool,&optional)==kCVReturnSuccess,let buffer=optional else { throw NSError(domain:"MascotMovie",code:6) }
            CVPixelBufferLockBaseAddress(buffer,[])
            let sample=flight.sample(at:Double(frame)/Double(fps))
            guard let context=CGContext(data:CVPixelBufferGetBaseAddress(buffer),width:width,height:height,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(buffer),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo.byteOrder32Little.rawValue|CGImageAlphaInfo.premultipliedFirst.rawValue) else { CVPixelBufferUnlockBaseAddress(buffer,[]);throw NSError(domain:"MascotMovie",code:7) }
            context.clear(bounds)
            draw(character,sample:sample,context:context,bounds:bounds,anchor:anchor)
            // Review stills are rendered from the same scene, not captured from the display.
            if [8,40,80,130].contains(frame),let image=context.makeImage() {
                let png=url.deletingPathExtension().appendingPathExtension("frame-\(frame).png")
                if let destination=CGImageDestinationCreateWithURL(png as CFURL,UTType.png.identifier as CFString,1,nil) { CGImageDestinationAddImage(destination,image,nil);CGImageDestinationFinalize(destination) }
            }
            CVPixelBufferUnlockBaseAddress(buffer,[])
            guard adaptor.append(buffer,withPresentationTime:CMTime(value:Int64(frame),timescale:fps)) else { throw writer.error ?? NSError(domain:"MascotMovie",code:8) }
        }
        input.markAsFinished()
        let done=DispatchSemaphore(value:0);writer.finishWriting{done.signal()}
        guard done.wait(timeout:.now()+30) == .success,writer.status == .completed else { throw writer.error ?? NSError(domain:"MascotMovie",code:9) }
    }
    private static func draw(_ character:MascotSpec,sample:MascotSample,context:CGContext,bounds:CGRect,anchor:CGPoint) {
        context.saveGState()
        let card=CGRect(x:anchor.x-44,y:anchor.y-72,width:360,height:144)
        context.setFillColor(NSColor(calibratedRed:0.1,green:0.12,blue:0.16,alpha:1).cgColor)
        context.addPath(CGPath(roundedRect:card,cornerWidth:16,cornerHeight:16,transform:nil));context.fillPath()
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:context,flipped:false)
        (character.name+" · Your update is ready").draw(at:CGPoint(x:card.minX+88,y:card.maxY-38),withAttributes:[.font:NSFont.systemFont(ofSize:14,weight:.semibold),.foregroundColor:NSColor.white])
        "Real sprites. A little magic.".draw(at:CGPoint(x:card.minX+88,y:card.midY-4),withAttributes:[.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor.lightGray])
        "Open app ↗".draw(at:CGPoint(x:card.minX+88,y:card.minY+25),withAttributes:[.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor.systemCyan])
        NSGraphicsContext.restoreGraphicsState()
        if character.motionClass == "magic",let t=sample.effectTime,let fx=SpriteLibrary.shared.effect() { context.draw(fx.frame(at:t),in:CGRect(x:sample.position.x-52,y:sample.position.y-48,width:104,height:104)) }
        let phase=sample.phase == .finished ? "exit" : sample.phase.rawValue
        if let animation=SpriteLibrary.shared.animation(character.id,phase,sample.facing) {
            context.setAlpha(sample.opacity)
            let h=sample.size,w=h*CGFloat(animation.spec.cellWidth)/CGFloat(animation.spec.cellHeight)
            if (sample.phase == .travel || sample.phase == .exit) && ["jet","magic"].contains(character.motionClass) {
                let pulse=CGFloat(0.7+0.3*sin(sample.phaseTime*27))
                context.setFillColor((character.motionClass == "jet" ? NSColor.systemOrange : NSColor.systemCyan).withAlphaComponent(0.7*pulse).cgColor)
                context.fillEllipse(in:CGRect(x:sample.position.x-7,y:sample.position.y-h*0.48-6,width:14,height:12+8*pulse))
            }
            context.interpolationQuality = .none
            context.draw(animation.frame(at:sample.phaseTime),in:CGRect(x:sample.position.x-w*character.pivot.x,y:sample.position.y-h*character.pivot.y,width:w,height:h))
        }
        context.restoreGState()
    }
}
