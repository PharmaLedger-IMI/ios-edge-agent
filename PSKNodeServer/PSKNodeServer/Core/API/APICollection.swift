//
//  APICollection.swift
//  PSKNodeServer
//
//  Created by Costin Andronache on 12.01.2022.
//

import PSSmartWalletNativeLayer
import GCDWebServers
import UIKit

struct APICollection {
    typealias APIInstance = (name: String, impl: APIImplementation)
    typealias StreamAPIInstance = (name: String, impl: StreamAPIImplementation)
    typealias PushStreamAPIInstance = (name: String, impl: PushStreamAPIImplementation)
    
    let apiList: [APIInstance]
    let streamAPIList: [StreamAPIInstance]
    let pushStreamAPIList: [PushStreamAPIInstance]
}


extension APICollection {
    static func setupAPICollection(webServer: GCDWebServer,
                                   viewControllerProvider: @autoclosure @escaping DataMatrixScanAPI.ViewControllerProvider) -> APICollection {
        /* This is the main function where each native API may be constructed/initialized */
        
        let dataMatrixAPI = setupDataMatrixScanAPI(viewControllerProvider: viewControllerProvider())
        let scanditScanAPI = setupScanditScanAPI(viewControllerProvider: viewControllerProvider())
        let jailbreakHeuristics = JailbreakHeuristics()
        
        let photoCaptureStreamAPI = setupPhotoCaptureStreamAPI()
        let photoCapturePushStreamAPI = setupPhotoCapturePushStreamAPI()
        let pharmaLedgerCameraAPI = PLCameraAPI(webServer: webServer)
        let pharmaLedgerCameraPushStreamAPI = PLCameraPushStreamAPI()
        
        return APICollection(apiList: [("dataMatrixScan", dataMatrixAPI),
                                       ("scanditScan", scanditScanAPI),
                                       ("jailbreakHeuristics", jailbreakHeuristics)],
                             streamAPIList: [("photoCaptureStream", photoCaptureStreamAPI),
                                             ("pharmaLedgerCameraAPI", pharmaLedgerCameraAPI)],
                             pushStreamAPIList: [("numbers", NumberPushStream()),
                                                 ("photoCapturePushStream", photoCapturePushStreamAPI),
                                                 ("pharmaLedgerCameraPushStreamAPI", pharmaLedgerCameraPushStreamAPI)])
    }
}

private extension APICollection {
    static func setupScanditScanAPI(viewControllerProvider: @autoclosure @escaping DataMatrixScanAPI.ViewControllerProvider) -> ScanditScanAPI {
        .init(viewControllerProvider: viewControllerProvider)
    }
}

private extension APICollection {
    static func setupDataMatrixScanAPI(viewControllerProvider: @autoclosure @escaping DataMatrixScanAPI.ViewControllerProvider) -> DataMatrixScanAPI {
        let camera2DMatrixScanModuleBuilder = CameraMetadataScanModuleBuilder(hostController: viewControllerProvider(),
                                                                              cameraScreenModuleBuilder: CameraScreenModuleBuilder(),
                                                                              searchedMetadataTypes: [.dataMatrix])
        return DataMatrixScanAPI(camera2DMatrixScanModuleBuilder: camera2DMatrixScanModuleBuilder)
    }
    
    static func setupPhotoCaptureStreamAPI() -> PhotoCaptureStreamAPI {
        .init(frameCaptureModuleBuilder: CameraFrameCaptureModuleBuilder(videoCaptureSessionModuleBuilder: VideoCaptureSessionModuleBuilders.VideoCaptureSessionModuleBuilder()))
    }
    
    static func setupPhotoCapturePushStreamAPI() -> PhotoCapturePushStreamAPI {
        .init(frameCaptureModuleBuilder: CameraFrameCaptureModuleBuilder(videoCaptureSessionModuleBuilder: VideoCaptureSessionModuleBuilders.VideoCaptureSessionModuleBuilder()))
    }
    
}
