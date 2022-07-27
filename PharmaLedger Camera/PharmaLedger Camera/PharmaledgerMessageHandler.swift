//
//  PharmaledgerMessageHandler.swift
//  PSKNodeServer
//  Created by Sergio Mota on 20/07/2021.
//  Based on file:
//  https://github.com/PharmaLedger-IMI/pharmaledger-camera/blob/feature/jscamera/WkCamera/WkCamera/JsMessageHandler.swift
//  JsMessageHandler.swift
//  jscamera
//
//  Created by Yves Delacrétaz on 29.06.21.
//  Updated from code @ 01.102021 https://github.com/PharmaLedger-IMI/pharmaledger-camera/commit/4847c378127f5d0b6d240c5ca36b1df916bc9ed8
//

import Foundation
import WebKit
import AVFoundation
import Accelerate
import GCDWebServers

public class PharmaledgerMessageHandler: NSObject, CameraEventListener {
    // MARK: privates vars
    private var hasOwnWebserver = false
    private var ypCbCrPixelRange = vImage_YpCbCrPixelRange(Yp_bias: 0,
                                                     CbCr_bias: 128,
                                                     YpRangeMax: 255,
                                                     CbCrRangeMax: 255,
                                                     YpMax: 255,
                                                     YpMin: 0,
                                                     CbCrMax: 255,
                                                     CbCrMin: 0)
    private var argbToYpCbCr: vImage_ARGBToYpCbCr {
        var outInfo = vImage_ARGBToYpCbCr()
        
        vImageConvert_ARGBToYpCbCr_GenerateConversion(kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2,
                                                      &ypCbCrPixelRange,
                                                      &outInfo,
                                                      kvImageARGB8888,
                                                      kvImage420Yp8_CbCr8,
                                                      vImage_Flags(kvImageNoFlags))
        return outInfo
    }
    
    private var dataBuffer_w = -1
    private var dataBuffer_h = -1
    private var dataBufferRGBA: UnsafeMutableRawPointer? = nil
    private var dataBufferRGB: UnsafeMutableRawPointer? = nil
    private var dataBufferYp: UnsafeMutableRawPointer? = nil
    private var dataBufferCbCr: UnsafeMutableRawPointer? = nil
    private var dataBufferRGBsmall: UnsafeMutableRawPointer? = nil
    private var rawData = Data()
    private var previewData = Data()
    private var currentCIImage: CIImage? = nil
    private var webview: WKWebView? = nil
    private var onGrabFrameJsCallBack: String?
    private let ciContext = CIContext(options: nil)
    private var previewWidth = 640;
    private var previewHeight = -1;
    private var onCaptureJsCallback: String?
    private let mjpegQueue = DispatchQueue(label: "stream-queue", qos: .userInteractive, attributes: [], autoreleaseFrequency: .workItem, target: nil)
    private let rawframeQueue = DispatchQueue(label: "rawframe-queue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem, target: nil)
    private let previewframeQueue = DispatchQueue(label: "previewframe-queue", qos: .userInteractive, attributes: [], autoreleaseFrequency: .workItem, target: nil)
    
    private var onJPEGBase64Ready: ((String) -> Void)?
    private var onCameraInitializedHandler: (() -> Void)?
    private var onCameraPermissionDeniedHandler: (() -> Void)?
    
    // MARK: public vars
    public var cameraSession: CameraSession?
    public var cameraConfiguration: CameraConfiguration?
        

    public func setupInWebServer(webserver: GCDWebServer) {
        addWebserverHandlers(webserver: webserver)
    }
                
    // MARK: CameraEventListener Protocol
    public func onCameraPermissionDenied() {
        onCameraPermissionDeniedHandler?()
    }
    
    public func onPreviewFrame(sampleBuffer: CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Cannot get imageBuffer")
            return
        }
        currentCIImage = CIImage(cvImageBuffer: imageBuffer, options: nil)
    }
    
    public func onCapture(imageData: Data) {
        let base64 = "data:image/jpeg;base64, " + imageData.base64EncodedString()
        onJPEGBase64Ready?(base64)
    }
    
    public func onCameraInitialized() {
        onCameraInitializedHandler?()
    }
    
    // MARK: Public interface
    
    public func startCamera(args: [String: Any],
                            cameraReadyHandler: (() -> Void)?,
                            permissionDeniedHandler: (() -> Void)?) {
        if let pWidth = args["previewWidth"] as? Int {
            self.previewWidth = pWidth
        }
        
        handleCameraStart(sessionPreset: args["sessionPreset"] as! String,
                          flash_mode: args["flashMode"] as? String,
                          auto_orientation_enabled: args["auto_orientation_enabled"] as? Bool)
        onCameraInitializedHandler = cameraReadyHandler
        onCameraPermissionDeniedHandler = permissionDeniedHandler
    }
    
    public func startCameraWithConfig(args: [String: Any],
                                      cameraReadyHandler: (() -> Void)?,
                                      permissionDeniedHandler: (() -> Void)?) {
        onCameraInitializedHandler = cameraReadyHandler
        onCameraPermissionDeniedHandler = permissionDeniedHandler
        
        if let pWidth = args["previewWidth"] as? Int {
            self.previewWidth = pWidth
        }
        
        if let configDict = args["config"] as? [String: Any] {
            handleCameraStart(configDict: configDict)
        } else {
            handleCameraStart(configDict: [:])
        }
    }
    
    public func stopCameraSession() {
        if let cameraSession = self.cameraSession {
            if let captureSession = cameraSession.captureSession {
                if captureSession.isRunning {
                    cameraSession.stopCamera()
                }
            }
        }
        self.cameraConfiguration = nil
        self.cameraSession = nil
        if dataBufferRGBA != nil {
            free(dataBufferRGBA!)
            dataBufferRGBA = nil
        }
        if dataBufferRGB != nil {
            free(dataBufferRGB)
            dataBufferRGB = nil
        }
        if dataBufferYp != nil {
            free(dataBufferYp)
            dataBufferYp = nil
        }
        if dataBufferCbCr != nil {
            free(dataBufferCbCr)
            dataBufferCbCr = nil
        }
        if dataBufferRGBsmall != nil {
            free(dataBufferRGBsmall)
            dataBufferRGBsmall = nil
        }
        self.previewWidth = -1
        self.previewHeight = -1
        dataBuffer_w = -1
        dataBuffer_h = -1
        self.currentCIImage = nil
    }
    
    public func setFlashMode(args: [String: Any]) {
        handleSetFlashMode(mode: args["mode"] as? String)
    }
    
    public func takeBase64Picture(args: [String: Any], completion: ((String) -> Void)?) {
        handleTakePicture(onCaptureBase64CaptureHandler: completion)
    }
    
    public func setTorchLevel(args: [String: Any]) {
        if let level = args["level"] as? NSNumber {
            let levelVal = level.floatValue
            if levelVal > 0.0 {
                handleSetTorchLevel(level: levelVal)
            } else {
                print("Torch level must be greater than 0.0")
            }
        } else {
            print("JsMessageHandler: cannot convert argument to NSNumber")
            return
        }
    }
    
    public func setColorSpace(args: [String: Any]) {
        if let colorspace = args["colorspace"] as? String {
            if let cameraConfiguration = self.cameraConfiguration {
                cameraConfiguration.setPreferredColorSpace(color_space: colorspace)
                cameraConfiguration.applyConfiguration()
            }
        } else {
            print("JsMessageHandler: cannot convert argument to String")
            return
        }
    }
        
    // MARK: private methods
    private func enforceRawBuffer(cgImage: CGImage) {
        if cgImage.width != dataBuffer_w || cgImage.height != dataBuffer_h {
            if dataBufferRGBA != nil {
                free(dataBufferRGBA)
                dataBufferRGBA = nil
            }
            if dataBufferRGB != nil {
                free(dataBufferRGB)
                dataBufferRGB = nil
            }
            if dataBufferYp != nil {
                free(dataBufferYp)
                dataBufferYp = nil
            }
            if dataBufferCbCr != nil {
                free(dataBufferCbCr)
                dataBufferCbCr = nil
            }
        }
        if dataBufferRGBA == nil {
            dataBufferRGBA = malloc(cgImage.bytesPerRow*cgImage.height)
            dataBuffer_w = cgImage.width
            dataBuffer_h = cgImage.height
        }
        if dataBufferRGB == nil {
            dataBufferRGB = malloc(3*cgImage.width*cgImage.height)
        }
        if dataBufferYp == nil {
            dataBufferYp = malloc(cgImage.width*cgImage.height)
        }
        if dataBufferCbCr == nil {
            dataBufferCbCr = malloc(cgImage.width*cgImage.height / 2)
        }
    }
    
    private func buildRgba_vImage(cgImage: CGImage, vimage: inout vImage_Buffer) {
        enforceRawBuffer(cgImage: cgImage)
        let colorspace = CGColorSpaceCreateDeviceRGB()
        let cgContext = CGContext(data: dataBufferRGBA, width: cgImage.width, height: cgImage.height, bitsPerComponent: cgImage.bitsPerComponent, bytesPerRow: cgImage.bytesPerRow, space: colorspace, bitmapInfo: cgImage.bitmapInfo.rawValue)
        
        cgContext?.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        vimage = vImage_Buffer(
            data: dataBufferRGBA!,
            height: vImagePixelCount(cgImage.height),
            width: vImagePixelCount(cgImage.width),
            rowBytes: cgImage.bytesPerRow)
    }
    
    private func prepareRGBData(ciImage: CIImage, roi: CGRect?) -> Data {
        let extent: CGRect = roi ?? ciImage.extent
        guard let cgImage = ciContext.createCGImage(ciImage, from: extent) else {
            return Data()
        }
        var inBuffer: vImage_Buffer = vImage_Buffer()
        buildRgba_vImage(cgImage: cgImage, vimage: &inBuffer)
        var outBuffer = vImage_Buffer(
            data: dataBufferRGB,
            height: vImagePixelCount(cgImage.height),
            width: vImagePixelCount(cgImage.width),
            rowBytes: 3*cgImage.width)
        vImageConvert_RGBA8888toRGB888(&inBuffer, &outBuffer, UInt32(kvImageNoFlags))
        
        let data = Data(bytesNoCopy: dataBufferRGB!, count: 3*cgImage.width*cgImage.height, deallocator: .none)
        return data
    }
    
    private func prepare420Yp8_CbCr8Data(ciImage: CIImage, roi: CGRect?) -> Data {
        let extent: CGRect = roi ?? ciImage.extent
        guard let cgImage = ciContext.createCGImage(ciImage, from: extent) else {
            return Data()
        }
        var inBuffer: vImage_Buffer = vImage_Buffer()
        buildRgba_vImage(cgImage: cgImage, vimage: &inBuffer)
        var ypOut = vImage_Buffer(data: dataBufferYp, height: vImagePixelCount(cgImage.height), width: vImagePixelCount(cgImage.width), rowBytes: cgImage.width)
        var cbCrOut = vImage_Buffer(data: dataBufferCbCr, height: vImagePixelCount(cgImage.height/2), width: vImagePixelCount(cgImage.width/2), rowBytes: cgImage.width)
        _ = withUnsafePointer(to: argbToYpCbCr, {info in
            vImageConvert_ARGB8888To420Yp8_CbCr8(&inBuffer, &ypOut, &cbCrOut, info, [3, 0, 1, 2], vImage_Flags(kvImagePrintDiagnosticsToConsole))
        })
        let dataYp = Data(bytesNoCopy: dataBufferYp!, count: cgImage.width*cgImage.height, deallocator: .none)
        let dataCbCr = Data(bytesNoCopy: dataBufferCbCr!, count: cgImage.width*cgImage.height/2, deallocator: .none)
        var fullData = Data()
        fullData.append(dataYp)
        fullData.append(dataCbCr)
        return fullData
    }
    
    private func preparePreviewData(ciImage: CIImage) -> (Data, Int, Int) {
        let resizeFilter = CIFilter(name: "CILanczosScaleTransform")!
        resizeFilter.setValue(ciImage, forKey: kCIInputImageKey)
        let previewHeight = Int(CGFloat(ciImage.extent.height) / CGFloat(ciImage.extent.width) * CGFloat(self.previewWidth))
        if self.previewHeight != previewHeight {
            self.previewHeight = previewHeight
            if dataBufferRGBsmall != nil {
                free(dataBufferRGBsmall)
                dataBufferRGBsmall = nil
            }
            dataBufferRGBsmall = malloc(3*self.previewHeight*self.previewWidth)
        }
        let scale = CGFloat(previewHeight) / ciImage.extent.height
        let ratio = CGFloat(self.previewWidth) / CGFloat(ciImage.extent.width) / scale
        resizeFilter.setValue(scale, forKey: kCIInputScaleKey)
        resizeFilter.setValue(ratio, forKey: kCIInputAspectRatioKey)
        let ciImageRescaled = resizeFilter.outputImage!
        //
        guard let cgImage = ciContext.createCGImage(ciImageRescaled, from: ciImageRescaled.extent) else {
            return (Data(), -1, -1)
        }
        let colorspace = CGColorSpaceCreateDeviceRGB()
        let bpc = cgImage.bitsPerComponent
        let Bpr = cgImage.bytesPerRow
        let cgContext = CGContext(data: nil, width: cgImage.width, height: cgImage.height, bitsPerComponent: bpc, bytesPerRow: Bpr, space: colorspace, bitmapInfo: cgImage.bitmapInfo.rawValue)

        cgContext?.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        var inBufferSmall = vImage_Buffer(
            data: cgContext!.data!,
            height: vImagePixelCount(cgImage.height),
            width: vImagePixelCount(cgImage.width),
            rowBytes: Bpr)
        var outBufferSmall = vImage_Buffer(
            data: dataBufferRGBsmall,
            height: vImagePixelCount(cgImage.height),
            width: vImagePixelCount(cgImage.width),
            rowBytes: 3*cgImage.width)
        vImageConvert_RGBA8888toRGB888(&inBufferSmall, &outBufferSmall, UInt32(kvImageNoFlags))
        let data = Data(bytesNoCopy: dataBufferRGBsmall!, count: 3*cgImage.width*cgImage.height, deallocator: .none)
        return (data, self.previewWidth, previewHeight)
    }
    
    public func getRawFrame(roi: CGRect?) -> (data: Data, width: CGFloat, height: CGFloat)? {
        if let ciImage = self.currentCIImage {
            let data = self.prepareRGBData(ciImage: ciImage, roi: roi)
            let imageSize: CGSize = roi?.size ?? ciImage.extent.size
            return (data, imageSize.width, imageSize.height)
        }
        
        return nil
    }
    
    public func getRawFrameYCBCR(roi: CGRect?) -> (data: Data, width: Int, height: Int)? {
        if let ciImage = self.currentCIImage {
            let data = self.prepare420Yp8_CbCr8Data(ciImage: ciImage, roi: roi)
            let imageSize: CGSize = roi?.size ?? ciImage.extent.size
            return (data, Int(imageSize.width), Int(imageSize.height))
        }
        return nil
    }
    
    public func gePreviewFrame() -> (data: Data, width: Int, height: Int)? {
        if let ciImage = self.currentCIImage {
            return self.preparePreviewData(ciImage: ciImage)
        }
        return nil
    }
    
    public func getJPEGSnapshot(completion: @escaping (Data?) -> Void) {
        DispatchQueue.global().async {
            let semaphore = DispatchSemaphore(value: 0)
            let photoSettings = AVCapturePhotoSettings()
            photoSettings.isHighResolutionPhotoEnabled = true
            guard let flashMode = self.cameraSession?.getConfig()?.getFlashMode() else {
                completion(nil)
                return
            }
            photoSettings.flashMode = flashMode
            let processor = CaptureProcessor(completion: {data in
                completion(data)
                semaphore.signal()
            })
            guard let photoOutput = self.cameraSession?.getPhotoOutput() else {
                completion(nil)
                return
            }
            photoOutput.capturePhoto(with: photoSettings, delegate: processor)
            _ = semaphore.wait(timeout: DispatchTime.now().advanced(by: DispatchTimeInterval.seconds(10)))
        }
    }
    
    public func getCameraConfig() -> [String: Any] {
        cameraConfiguration?.toDict() ?? [:]
    }
    
    public func getDeviceInfo() -> [String: Any] {
        UIDevice.getDeviceInfo()
    }
    
    // MARK: webserver endpoints definitions
    private func addWebserverHandlers(webserver: GCDWebServer) {
        webserver.addHandler(forMethod: "GET", path: "/mjpeg", request: GCDWebServerRequest.classForCoder(), asyncProcessBlock: {(request, completion) in
            let response = GCDWebServerStreamedResponse(contentType: "multipart/x-mixed-replace; boundary=0123456789876543210", asyncStreamBlock: {completion in
                self.mjpegQueue.async {
                    if let ciImage = self.currentCIImage {
                        if let tempImage = self.ciContext.createCGImage(ciImage, from: ciImage.extent) {
                            let image = UIImage(cgImage: tempImage)
                            let jpegData = image.jpegData(compressionQuality: 0.5)!
                            
                            let frameHeaders = [
                                "",
                                "--0123456789876543210",
                                "Content-Type: image/jpeg",
                                "Content-Length: \(jpegData.count)",
                                "",
                                ""
                            ]
                            if let frameHeadersData = frameHeaders.joined(separator: "\r\n").data(using: String.Encoding.utf8) {
                                var allData = Data()
                                allData.append(frameHeadersData)
                                allData.append(jpegData)
                                let footersData = ["", ""].joined(separator: "\r\n").data(using: String.Encoding.utf8)!
                                allData.append(footersData)
                                completion(allData, nil)
                            } else {
                                print("Could not make frame headers data")
                                completion(nil, StreamResponseError.cannotCreateFrameHeadersData)
                            }
                        } else {
                            completion(nil, StreamResponseError.cannotCreateCGImage)
                        }
                    } else {
                        completion(nil, StreamResponseError.cannotCreateCIImage)
                    }
                }
            })
            response.setValue("keep-alive", forAdditionalHeader: "Connection")
            response.setValue("0", forAdditionalHeader: "Ma-age")
            response.setValue("0", forAdditionalHeader: "Expires")
            response.setValue("no-store,must-revalidate", forAdditionalHeader: "Cache-Control")
            response.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
            response.setValue("accept,content-type", forAdditionalHeader: "Access-Control-Allow-Headers")
            response.setValue("GET", forAdditionalHeader: "Access-Control-Allow-Methods")
            response.setValue("Cache-Control,Content-Encoding", forAdditionalHeader: "Access-Control-expose-headers")
            response.setValue("no-cache", forAdditionalHeader: "Pragma")
            completion(response)
        })
        
        webserver.addHandler(forMethod: "GET", path: "/rawframe", request: GCDWebServerRequest.classForCoder(), asyncProcessBlock: { (request, completion) in
            self.rawframeQueue.async {
                var roi: CGRect? = nil
                if let query = request.query {
                    if query.count > 0 {
                        guard let x = query["x"], let y = query["y"], let w = query["w"], let h = query["h"] else {
                            let response = GCDWebServerErrorResponse.init(text: "Must specify exactly 4 params (x, y, w, h) or none.")
                            response?.statusCode = 400
                            completion(response)
                            return
                        }
                        guard let x = Int(x), let y = Int(y), let w = Int(w), let h = Int(h) else {
                            let response = GCDWebServerErrorResponse.init(text: "(x, y, w, h) must be integers.")
                            response?.statusCode = 400
                            completion(response)
                            return
                        }
                        roi = CGRect(x: x, y: y, width: w, height: h)
                    }
                }
                if let ciImage = self.currentCIImage {
                    let data = self.prepareRGBData(ciImage: ciImage, roi: roi)
                    let contentType = "application/octet-stream"
                    let response = GCDWebServerDataResponse(data: data, contentType: contentType)
                    response.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
                    let imageSize: CGSize = roi?.size ?? ciImage.extent.size
                    response.setValue(String(Int(imageSize.width)), forAdditionalHeader: "image-width")
                    response.setValue(String(Int(imageSize.height)), forAdditionalHeader: "image-height")
                    response.setValue("image-width,image-height", forAdditionalHeader: "Access-Control-Expose-Headers")
                    completion(response)
                } else {
                    completion(GCDWebServerErrorResponse.init(statusCode: 500))
                }
            }
        })
        webserver.addHandler(forMethod: "GET", path: "/rawframe_ycbcr", request: GCDWebServerRequest.classForCoder(), asyncProcessBlock: { (request, completion) in
            self.rawframeQueue.async {
                var roi: CGRect? = nil
                if let query = request.query {
                    if query.count > 0 {
                        guard let x = query["x"], let y = query["y"], let w = query["w"], let h = query["h"] else {
                            let response = GCDWebServerErrorResponse.init(text: "Must specify exactly 4 params (x, y, w, h) or none.")
                            response?.statusCode = 400
                            completion(response)
                            return
                        }
                        guard let x = Int(x), let y = Int(y), let w = Int(w), let h = Int(h) else {
                            let response = GCDWebServerErrorResponse.init(text: "(x, y, w, h) must be integers.")
                            response?.statusCode = 400
                            completion(response)
                            return
                        }
                        roi = CGRect(x: x, y: y, width: w, height: h)
                    }
                }
                if let ciImage = self.currentCIImage {
                    let data = self.prepare420Yp8_CbCr8Data(ciImage: ciImage, roi: roi)
                    let contentType = "application/octet-stream"
                    let response = GCDWebServerDataResponse(data: data, contentType: contentType)
                    let imageSize: CGSize = roi?.size ?? ciImage.extent.size
                    response.setValue(String(Int(imageSize.width)), forAdditionalHeader: "image-width")
                    response.setValue(String(Int(imageSize.height)), forAdditionalHeader: "image-height")
                    response.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
                    response.setValue("image-width,image-height", forAdditionalHeader: "Access-Control-Expose-Headers")
                    completion(response)
                } else {
                    completion(GCDWebServerErrorResponse.init(statusCode: 500))
                }
            }
        })
        
        webserver.addHandler(forMethod: "GET", path: "/previewframe", request: GCDWebServerRequest.self, asyncProcessBlock: {(request, completion) in
            self.previewframeQueue.async {
                if let ciImage = self.currentCIImage {
                    let (data, w, h) = self.preparePreviewData(ciImage: ciImage)
                    let contentType = "application/octet-stream"
                    let response = GCDWebServerDataResponse(data: data, contentType: contentType)
                    response.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
                    response.setValue(String(w), forAdditionalHeader: "image-width")
                    response.setValue(String(h), forAdditionalHeader: "image-height")
                    response.setValue("image-width,image-height", forAdditionalHeader: "Access-Control-Expose-Headers")
                    completion(response)
                } else {
                    completion(GCDWebServerErrorResponse(statusCode: 500))
                }
            }
        })
        
        webserver.addHandler(forMethod: "GET", path: "/snapshot", request: GCDWebServerRequest.classForCoder(), asyncProcessBlock: {(request, completion) in
            DispatchQueue.global().async {
                let semaphore = DispatchSemaphore(value: 0)
                let photoSettings = AVCapturePhotoSettings()
                photoSettings.isHighResolutionPhotoEnabled = true
                guard let flashMode = self.cameraSession?.getConfig()?.getFlashMode() else {
                    completion(nil)
                    return
                }
                photoSettings.flashMode = flashMode
                var response: GCDWebServerResponse? = nil
                let processor = CaptureProcessor(completion: {data in
                    let contentType = "image/jpeg"
                    response = GCDWebServerDataResponse(data: data, contentType: contentType)
                    response?.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
                    semaphore.signal()
                })
                guard let photoOutput = self.cameraSession?.getPhotoOutput() else {
                    completion(nil)
                    return
                }
                photoOutput.capturePhoto(with: photoSettings, delegate: processor)
                _ = semaphore.wait(timeout: DispatchTime.now().advanced(by: DispatchTimeInterval.seconds(10)))
                completion(response)
            }
        })
        
        webserver.addHandler(forMethod: "GET", path: "/cameraconfig", request: GCDWebServerRequest.classForCoder(), processBlock: {request in
            var response: GCDWebServerDataResponse!
            let cameraConfigDict: [String: AnyObject] = self.cameraConfiguration?.toDict() ?? [String: AnyObject]()
            response = GCDWebServerDataResponse(jsonObject: cameraConfigDict)
            response.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
            return response
        })
        
        webserver.addHandler(forMethod: "GET", path: "/deviceinfo", request: GCDWebServerRequest.classForCoder(), processBlock: {rerquest in
            let deviceInfoDict = UIDevice.getDeviceInfo()
            if let response = GCDWebServerDataResponse(jsonObject: deviceInfoDict) {
                response.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
                return response
            } else {
                return nil
            }
        })
    }
    
    // MARK: Public functionalities
    public func startCameraSessionWith(configuration: CameraConfiguration) {
        self.cameraConfiguration = configuration
        self.cameraSession = .init(cameraEventListener: self, cameraConfiguration: self.cameraConfiguration!)
    }
    
    // MARK: js message handlers implementations
    private func handleCameraStart(sessionPreset: String,
                                   flash_mode: String?,
                                   auto_orientation_enabled: Bool?) {
        let configuration: CameraConfiguration = .init(flash_mode: flash_mode, color_space: nil, session_preset: sessionPreset, device_types: ["wideAngleCamera"], camera_position: "back", continuous_focus: true, highResolutionCaptureEnabled: true, auto_orientation_enabled: auto_orientation_enabled ?? false)
        startCameraSessionWith(configuration: configuration)
    }
    
    private func handleCameraStart(configDict: [String: Any]) {
        startCameraSessionWith(configuration: CameraConfiguration.createFromConfig(configDict: configDict))
    }
    
    private func handleTakePicture(onCaptureBase64CaptureHandler: ((String) -> Void)?) {
        self.onJPEGBase64Ready = onCaptureBase64CaptureHandler
        self.cameraSession?.takePicture()
    }
    
    private func handleSetFlashMode(mode: String?) {
        guard let mode = mode, let cameraConfiguration = cameraConfiguration else {
            return
        }
        cameraConfiguration.setFlashConfiguration(flash_mode: mode)
        if let cameraSession = self.cameraSession {
            if let captureSession = cameraSession.captureSession {
                if captureSession.isRunning {
                    cameraConfiguration.applyConfiguration()
                }
            }
        }
    }
    
    private func handleSetTorchLevel(level: Float) {
        guard let cameraConfiguration = cameraConfiguration else {
            return
        }
        cameraConfiguration.setTorchLevel(level: level)
        if let cameraSession = self.cameraSession {
            if let captureSession = cameraSession.captureSession {
                if captureSession.isRunning {
                    cameraConfiguration.applyConfiguration()
                }
            }
        }
    }
}

public extension PharmaledgerMessageHandler {
    enum MessageName: String, Decodable, CaseIterable {
        case StartCamera = "StartCamera"
        case StartCameraWithConfig = "StartCameraWithConfig"
        case StopCamera = "StopCamera"
        case TakePicture = "TakePicture"
        case SetFlashMode = "SetFlashMode"
        case SetTorchLevel = "SetTorchLevel"
        case SetPreferredColorSpace = "SetPreferredColorSpace"
    }

    enum StreamResponseError: Error {
        case cannotCreateCIImage
        case cannotCreateCGImage
        case cannotCreateFrameHeadersData
    }
}

//extension GCDWebServerResponse {
//    func applyCORSHeaders() -> Self {
//        let resp = self
//        resp.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
//        resp.setValue("*", forAdditionalHeader: "Access-Control-Allow-Methods")
//        resp.setValue("*", forAdditionalHeader: "Access-Control-Allow-Headers")
//        resp.setValue("true", forAdditionalHeader: "Access-Control-Allow-Credentials")
//        return self
//    }
//}

