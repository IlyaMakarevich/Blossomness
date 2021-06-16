//
//  ViewController.swift
//  Blossomness
//
//  Created by Ilya Makarevich on 6/14/21.
//

import UIKit
import AVFoundation
import Vision
import SnapKit


struct PLNLocalRecognizerPlantModel {
    let name: String
    let percentage: Double
}

typealias LocalRecognizeResultHandler = ((_ result: [PLNLocalRecognizerPlantModel]) -> Void)


class ViewController: UIViewController {
    @IBOutlet private weak var previewView: UIView!
    @IBOutlet private weak var boundingBoxView: BoundingBoxView!
    @IBOutlet private weak var smallPreviewImageView: UIImageView!
    @IBOutlet private weak var classificationLabel: UILabel!
    
    private let limit = 6
    private var results: [[PLNLocalRecognizerPlantModel]] = []

    private var cameraOutput: CIImage!
    
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
    
    @IBAction func resetAction(_ sender: Any) {
        smallPreviewImageView.image = nil
        status = .notStarted
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupRecognitionModelAndRequest()
        setupVideoPreview()
        
        smallPreviewImageView.alpha = 0
        classificationLabel.alpha = 0
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
            if self.status != .searched {
                self.smallPreviewImageView.image = self.cutScreenshot(rect: rect)
            }
        }
    }
    
    private func cutScreenshot(rect: CGRect) -> UIImage? {
        guard let cameraOutput = self.cameraOutput else { return nil }
        if let fullCGImage = convertCIImageToCGImage(inputImage: cameraOutput) {
            if let cropped = fullCGImage.cropping(to: rect) {
                if status != .searched {
                    updateClassifications(for: UIImage(cgImage: cropped))
                }
                return UIImage(cgImage: cropped)
            } else {
                return nil
            }
        } else {
            return nil
        }
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
                    let pottedPlantPrediction = predictions.first { $0.labels.first?.identifier == "pottedplant" }
                        DispatchQueue.main.async {
                            if let pottedPlantPrediction = pottedPlantPrediction {
                                self.boundingBoxView.predictedObjects = [pottedPlantPrediction]
                            } else {
                                self.boundingBoxView.predictedObjects = []
                                //self.smallPreviewImageView.image = nil
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
    
    func convertCIImageToCGImage(inputImage: CIImage) -> CGImage? {
        let context = CIContext(options: nil)
        if let cgImage = context.createCGImage(inputImage, from: inputImage.extent) {
            return cgImage
        }
        return nil
    }
    
    private func startAnimation() {
        smallPreviewImageView.snp.remakeConstraints { make in
            make.size.equalTo(150)
        }
        UIView.animate(withDuration: 1.0) {
            self.smallPreviewImageView.alpha = 1
            self.classificationLabel.alpha = 1
            self.view.layoutIfNeeded()
        }
    }
}

extension ViewController: VideoCaptureDelegate {
    func videoCapture(_ capture: VideoCapture, pixelBuffer: CVPixelBuffer?, timestamp: CMTime) {
        if !self.isInferencing, let pixelBuffer = pixelBuffer {
            cameraOutput = CIImage(cvPixelBuffer: pixelBuffer)
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
        let request = VNCoreMLRequest(model: model) { request, _  in
            self.processObservations(for: request) { [weak self] (models) in
                guard let self = self else { return }
                guard !models.isEmpty else { return }
                                
                let detectedPlantClass = models[0]
                if detectedPlantClass.name == "unknown-plant" || detectedPlantClass.name == "notplant" {
                    self.classificationLabel.text = "searching..."
                } else if detectedPlantClass.percentage >= 90 {
                    self.status = .searched
                    self.classificationLabel.text = detectedPlantClass.name
                    self.startAnimation()
                } else {
                    self.classificationLabel.text = "searching..."
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    //self.status = .notStarted
                }
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
    
    private func processObservations(for request: VNRequest, completion: LocalRecognizeResultHandler?) {
        if let observResult = request.results, let observList = observResult as? [VNClassificationObservation] {
            let observations = observList.prefix(limit)
            let results = observations.map { observation -> PLNLocalRecognizerPlantModel in
                let formatter = NumberFormatter()
                formatter.maximumFractionDigits = 1
                return PLNLocalRecognizerPlantModel(name: observation.identifier, percentage: Double(observation.confidence * 100))
            }

            DispatchQueue.main.async {
                completion?(results)
            }
        } else {
            DispatchQueue.main.async {
                completion?([])
            }
        }
    }
    
}

