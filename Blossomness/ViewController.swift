//
//  ViewController.swift
//  Blossomness
//
//  Created by Ilya Makarevich on 6/14/21.
//

import UIKit
import AVFoundation
import Vision

class ViewController: UIViewController {
    @IBOutlet private weak var previewView: UIView!
    @IBOutlet private weak var boundingBoxView: BoundingBoxView!
    @IBOutlet private weak var smallPreviewImageView: UIImageView!
    @IBOutlet private weak var classificationLabel: UILabel!
    
    
    private var cameraOutputSnapshot: UIImage!
    
    //MARK: - Vision Properties
    var visionRecognitionModel: VNCoreMLModel?
    var visionIdentificationModel: VNCoreMLModel?

    var recRequest: VNCoreMLRequest?

    var isInferencing = false
    
    let objectDetectionModel = YOLOv3()
    
    //MARK: - AV properties
    var videoCapture: VideoCapture!
    let semaphore = DispatchSemaphore(value: 1)
    var lastExecution = Date()
    
    var status = Status.notStarted {
      didSet {
        switch status {
        case .notStarted:
          print("not started")
        case .detecting:
          print("detecting")
        case .confirming:
          print("confirming")
        case .searching:
          print("searching")
        case .searched:
          print("searched")
        }
      }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupRecognitionModelAndRequest()
        setupVideoPreview()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.videoCapture.start()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        boundingBoxView.rectHandler = { [weak self] rect in
            guard let rect = rect, let self = self else { return }
            guard let cameraOutputSnapshot = self.cameraOutputSnapshot else { return }
            self.smallPreviewImageView.image = self.cropImage(cameraOutputSnapshot, toRect: rect, viewWidth: 100, viewHeight: 100)
        }
    }
    
//    private func cutScreenshot(rect: CGRect) -> UIImage? {
//        #warning("здесь cropped всегда nil непонятно почему")
//        if let cropped = cameraOutputSnapshot.cgImage?.cropping(to: rect) {
//            return UIImage(cgImage: cropped)
//        } else {
//            return nil
//        }
// /   }
    
    func cropImage(_ inputImage: UIImage, toRect cropRect: CGRect, viewWidth: CGFloat, viewHeight: CGFloat) -> UIImage?
    {
        let imageViewScale = max(inputImage.size.width / viewWidth,
                                 inputImage.size.height / viewHeight)

        // Scale cropRect to handle images larger than shown-on-screen size
        let cropZone = CGRect(x:cropRect.origin.x * imageViewScale,
                              y:cropRect.origin.y * imageViewScale,
                              width:cropRect.size.width * imageViewScale,
                              height:cropRect.size.height * imageViewScale)

        // Perform cropping in Core Graphics
        guard let cutImageRef: CGImage = inputImage.cgImage?.cropping(to:cropZone)
        else {
            return nil
        }

        // Return image to UIImage
        let croppedImage: UIImage = UIImage(cgImage: cutImageRef)
        return croppedImage
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.videoCapture.stop()
    }
    
    
    func setupRecognitionModelAndRequest() {
        if let model = try? VNCoreMLModel(for: objectDetectionModel.model) {
            visionRecognitionModel = model
            
            //setup request only once and run it multiple times
            recRequest = VNCoreMLRequest(model: visionRecognitionModel!, completionHandler: { (request, error) in
                if let predictions = request.results as? [VNRecognizedObjectObservation] {
                    let pottedPlantPredictions = predictions.filter {$0.labels.first?.identifier == "pottedplant"}
                        DispatchQueue.main.async {
                            if !pottedPlantPredictions.isEmpty {
                                self.boundingBoxView.predictedObjects = predictions
                            } else {
                                self.boundingBoxView.predictedObjects = []
                                self.smallPreviewImageView.image = nil
                            }
                            self.isInferencing = false
                        }
                    
                } else {
                    self.isInferencing = false
                }
                
                self.semaphore.signal()
            })
            
            recRequest?.imageCropAndScaleOption = .scaleFill
        } else {
            fatalError("Failed to create vision model and request")
        }
    }
    
    func runRequest(pixelBuffer: CVPixelBuffer) {
        guard let request = self.recRequest else { fatalError("No recognition request") }
        self.semaphore.wait()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)

        do {
            try handler.perform([request])
        } catch {
            print("Failed to perform request")
        }
    }
    
    func setupVideoPreview() {
        videoCapture = VideoCapture()
        videoCapture.delegate = self
        videoCapture.fps = 30
        
        videoCapture.setUp(sessionPreset: .inputPriority) { success in
            
            if success {
                // add preview view on the layer
                if let previewLayer = self.videoCapture.previewLayer {
                    self.previewView.layer.addSublayer(previewLayer)
                    self.resizePreviewLayer()
                }
                
                // start video preview when setup is done
                self.videoCapture.start()
            }
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        resizePreviewLayer()
    }
    
    func resizePreviewLayer() {
        videoCapture.previewLayer?.frame = previewView.bounds
    }
}

extension ViewController: VideoCaptureDelegate {
    func videoCapture(_ capture: VideoCapture, pixelBuffer: CVPixelBuffer?, timestamp: CMTime) {
        if !self.isInferencing, let pixelBuffer = pixelBuffer {
            cameraOutputSnapshot = UIImage(ciImage: CIImage(cvPixelBuffer: pixelBuffer))
            self.isInferencing = true
            self.runRequest(pixelBuffer: pixelBuffer)
        }
    }
    
    func updateClassifications(for image: UIImage) {
        guard let ciImage = CIImage(image: image) else { fatalError("Unable to create \(CIImage.self) from \(image).") }

        //TODO: Initialise model in a container
        guard let model = try? VNCoreMLModel(for: blossom150classes().model) else {
            fatalError("Model failed to initialise.")
        }
        //TODO: Define the VNCoreMLRequest
        let request = VNCoreMLRequest(model: model) { (req, err) in
            guard let result = req.results as? [VNClassificationObservation] else {
                fatalError("Request failed.")
            }
            if let firstResult = result.first {
                let description = String(format: "\(firstResult.identifier) - %.2f", firstResult.confidence)
                self.classificationLabel.text = description
            }
            
        }
        //TODO: set a request handler
        let handler = VNImageRequestHandler(ciImage: ciImage)
        //TODO: handle and run the request list
        do {
            try handler.perform([request])
        } catch {
            print("Handler failed.")
        }
    }
    
}

