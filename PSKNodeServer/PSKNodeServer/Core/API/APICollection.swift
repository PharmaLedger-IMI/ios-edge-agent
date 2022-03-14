//
//  APICollection.swift
//  PSKNodeServer
//
//  Created by Costin Andronache on 12.01.2022.
//

import PSSmartWalletNativeLayer
import UIKit

struct APICollection {
    typealias APIInstance = (name: String, impl: APIImplementation)
    typealias StreamAPIInstance = (name: String, impl: StreamAPIImplementation)
    
    let apiList: [APIInstance]
    let streamAPIList: [StreamAPIInstance]
}


extension APICollection {
    static func setupAPICollection(viewControllerProvider: @autoclosure @escaping DataMatrixScanAPI.ViewControllerProvider) -> APICollection {
        /* This is the main function where each native API may be constructed/initialized */
        
        let dataMatrixAPI = setupDataMatrixScanAPI(viewControllerProvider: viewControllerProvider())
        
        let scanditScanAPI = setupScanditScanAPI(viewControllerProvider: viewControllerProvider())
        let photoCaptureStreamAPI = setupPhotoCaptureStreamAPI()
        let pharmaLedgerCameraAPI = PLCameraAPI()
        
        return APICollection(apiList: [("dataMatrixScan", dataMatrixAPI),
                                       ("scanditScan", scanditScanAPI)],
                             streamAPIList: [("photoCaptureStream", photoCaptureStreamAPI),
                                             ("pharmaLedgerCameraAPI", pharmaLedgerCameraAPI)])
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
    
}
