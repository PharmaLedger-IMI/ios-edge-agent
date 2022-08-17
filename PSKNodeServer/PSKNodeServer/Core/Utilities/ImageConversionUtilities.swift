//
//  ImageConversionUtilities.swift
//  PSKNodeServer
//
//  Created by Costin Andronache on 11.02.2022.
//

import AVFoundation
import Accelerate
import UIKit

extension CVPixelBuffer {
    var width: Int {
        CVPixelBufferGetWidth(self)
    }
    
    var height: Int {
        CVPixelBufferGetHeight(self)
    }
    
    var bytesPerRow: Int {
        CVPixelBufferGetBytesPerRow(self)
    }
    
    var byteCount: Int {
        height * bytesPerRow
    }
    
    var rgba8888Width: Int {
        bytesPerRow / 4
    }
    
    func copyBGRABuffer(into: UnsafeMutableRawPointer? = nil) -> UnsafeMutableRawPointer? {
        CVPixelBufferLockBaseAddress(self, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(self, .readOnly)
        }
                
        guard let source = CVPixelBufferGetBaseAddress(self) else {
            return nil
        }
        
        let dest = into ?? UnsafeMutableRawPointer.allocate(byteCount: byteCount,
                                                            alignment: MemoryLayout<UInt32>.alignment)
        memcpy(dest, source, byteCount)
        return dest
    }
    
    func copyBGRAToRGBA(into: UnsafeMutableRawPointer? = nil) -> UnsafeMutableRawPointer? {
        let buffer = copyBGRABuffer(into: into)
        buffer?.swapBGRAtoRGBA(rows: UInt(height), width: UInt(width), rowBytes: bytesPerRow)
        
        return buffer
    }
    
    
    var asUIImage: UIImage? {
        let ciimage = CIImage(cvPixelBuffer: self)
        return ciimage.asUIImage
    }
}

extension UnsafeMutableRawPointer {
    func swapBGRAtoRGBA(rows: UInt, width: UInt, rowBytes: Int) {
        var src: vImage_Buffer = .init(data: self,
                                       height: rows,
                                       width: width,
                                       rowBytes: rowBytes)
        
        let permuteMap: [UInt8] = [2, 1, 0, 3]
        vImagePermuteChannels_ARGB8888(&src,
                                       &src,
                                       permuteMap,
                                       vImage_Flags(kvImagePrintDiagnosticsToConsole))
    }
}

extension UInt32 {
    var swappedBGRAtoRGBA: Self {
        let alphaMask: UInt32 = 255
        let redMask: UInt32 = 255 << 8
        let greenMask: UInt32 = 255 << 16
        let blueMask: UInt32 = 255 << 24
        
        let red: UInt32 = (self & redMask) << 16
        let green: UInt32 = (self & greenMask)
        let blue: UInt32 = (self & blueMask) >> 16
        let alpha: UInt32 = (self & alphaMask)
        
        return (red | green | blue | alpha)
        
    }
}

extension CIImage {
    var asUIImage: UIImage? {
        let context = CIContext(options: nil)
        let cgImage = context.createCGImage(self, from: self.extent)!
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
    }
}
