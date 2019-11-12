//
//  CameraFeedManager.swift
//  SinghaCapScanner
//
//  Created by katika kongsilp on 10/11/2562 BE.
//  Copyright © 2562 katika kongsilp. All rights reserved.
//

import UIKit
import AVFoundation

// learn again and again protocal
protocol CameraFeedManagerDelegate: class {
    /**
        This method delivers the pixel buffer of the current frame seen by the device's camera.
     */
    func didOutput(pixelBuffer: CVPixelBuffer)
    /**
        This method initimates that the camera permissions have benn denied
     */
    func presentCameraPermissionsDeniedAlert()
    /**
        This method initimates that a session runtime error occured.
     */
    func sessionRunTimeErrorOccured()
    /**
     This method initmates that a session runtime error occured
     */
    /**
     This method initimates that there was an error in video configurtion.
     */
    func presentVideoConfigurationErrorAlert()
    /**
    This method initimates that session was interrupted.
     */
    func sessionWasInterrupted(canResumeManually resumeManually: Bool)
    /**
     This method initmates that the session interruption has ended.
     */
    func sessionInterruptionEnded()
    
}

/**
 This enum holds the state of the camera initialzation.
 */
enum CameraConfiguration {
    case success
    case failed
    case permissionDenied
}

class CameraFeedManager: NSObject {
    // MARK: Camera Related Instance Variables
    private let session: AVCaptureSession = AVCaptureSession()
    private let previewView: PreviewView
    private let sessionQueue = DispatchQueue(label: "sessionQueue")
    private var cameraConfiguration: CameraConfiguration = .failed
    private lazy var videoDataOutput = AVCaptureVideoDataOutput()
    private var isSessionRunning = false
    
    // MARK: CameraFeedManagerDelegate
    weak var delegate: CameraFeedManagerDelegate?
    
    init(previewView: PreviewView) {
        self.previewView = previewView;
        super.init()
        
        // Initializes the session
        session.sessionPreset = .high
        self.previewView.session = session
        // this code maybe set the portrait camera ?????
        self.previewView.previewLayer.connection?.videoOrientation = .portrait
        // what is it ?????
        self.previewView.previewLayer.videoGravity = .resizeAspect
        self.attemptToConfigureSession()
    }
    
    // MARK: Session start and End methods
    /**
     This method starts an AVCaptureSession based on whether on whether the camera configuration wase successful.
     */
    func checkCameraConfigurationAndStartSession() {
        sessionQueue.async {
            switch self.cameraConfiguration {
            case .success:
                self.addObservers() // what ????
                self.startSession() //
            case .failed:
                DispatchQueue.main.async {
                    self.delegate?.presentVideoConfigurationErrorAlert()
                }
            case .permissionDenied:
                DispatchQueue.main.async {
                    self.delegate?.presentCameraPermissionsDeniedAlert()
                }
            }
        }
    }
    // ?? What is Observers
    // ?? Why we use that ?
    /**
     This method stops a running an AVCaptureSession.
     */
    func stopSession() {
        self.removeObservers()
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
            }
        }
    }
    /**
     This method resumes an interupted AVCaptureSession
     */
    func resumeInterruptedSession(withCompletion completion: @escaping (Bool) -> ()) {
        sessionQueue.async {
            self.startSession()
            DispatchQueue.main.async {
                completion(self.isSessionRunning)
            }
        }
    }
    /**
     This method stats the AVCaptureSession
     */
    private func startSession() {
        self.session.startRunning()
        self.isSessionRunning = self.session.isRunning
    }
    
    // MARK: Session Configuration Methods.
    /**
     This method requests for camera permissions and handles the configuration of the session and stores the result of configuration.
     */
    private func attemptToConfigureSession() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.cameraConfiguration = .success
        case .notDetermined:
            self.sessionQueue.suspend()
            self.requestCameraAccess(completion: { (granted) in
                self.sessionQueue.resume()
            })
        case .denied:
            self.cameraConfiguration = .permissionDenied
        default:
            break
        }
        
        self.sessionQueue.async {
            self.configureSession()
        }
    }
    /**
    This method requests for camera permissions.
     */
    private func requestCameraAccess(completion: @escaping (Bool) -> ()) {
        AVCaptureDevice.requestAccess(for: .video) { (granted) in
            if !granted {
                self.cameraConfiguration = .permissionDenied
            } else {
                self.cameraConfiguration = .success
            }
            completion(granted)
        }
    }
    /**
     This method handles all the steps to configure an AVCaptureSession.
     */
    //** session ???? to commitConfiguration
    private func configureSession() {
        guard cameraConfiguration == .success else {
            return
        }
        
        // Tries to add an AvCaptureDeviceInput
        guard addVideoDeviceInput() == true else {
            self.session.commitConfiguration()
            self.cameraConfiguration = .failed
            return
        }
        
        guard addVideoDataOutput() else {
            self.session.commitConfiguration()
            self.cameraConfiguration = .failed
            return
        }
        
        session.commitConfiguration()
        self.cameraConfiguration = .success
    }
    /**
     This method tries to an AVCaptureDeviceInput to the current ACCaptureSession.
     */
    
    private func addVideoDeviceInput() -> Bool {
        /** Tries to get default back camera*/
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            fatalError("Cannot find camera")
        }
        
        do {
            let videoDeviceInput = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                return true
            } else {
                return false
            }
        } catch {
            fatalError("Cannot create video device input")
        }
    }
    
    /**
     This method tries to an AVCaptureVideoDataOutput to the current AVCaptureSession.
     */
    private func addVideoDataOutput() -> Bool {
        let sampleBufferQueue = DispatchQueue(label: "sampleBufferQueue")
        videoDataOutput.setSampleBufferDelegate(self, queue: sampleBufferQueue)
        videoDataOutput.alwaysDiscardsLateVideoFrames = true// ?
        videoDataOutput.videoSettings = [
            String(kCVPixelBufferPixelFormatTypeKey): kCMPixelFormat_32ARGB]
        if session.canAddOutput(videoDataOutput) {
            videoDataOutput.connection(with: .video)?.videoOrientation = .portrait
            return true
        }
        return false
    }
    
    // MARK: Notification Observer Handling
     private func addObservers() {
       NotificationCenter.default.addObserver(self, selector: #selector(CameraFeedManager.sessionRuntimeErrorOccured(notification:)), name: NSNotification.Name.AVCaptureSessionRuntimeError, object: session)
       NotificationCenter.default.addObserver(self, selector: #selector(CameraFeedManager.sessionWasInterrupted(notification:)), name: NSNotification.Name.AVCaptureSessionWasInterrupted, object: session)
       NotificationCenter.default.addObserver(self, selector: #selector(CameraFeedManager.sessionInterruptionEnded), name: NSNotification.Name.AVCaptureSessionInterruptionEnded, object: session)
     }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVCaptureSessionRuntimeError, object: session)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVCaptureSessionWasInterrupted, object: session)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVCaptureSessionInterruptionEnded, object: session)
      }

      // MARK: Notification Observers
      @objc func sessionWasInterrupted(notification: Notification) {

        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
          let reasonIntegerValue = userInfoValue.integerValue,
          let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
          print("Capture session was interrupted with reason \(reason)")

          var canResumeManually = false
          if reason == .videoDeviceInUseByAnotherClient {
            canResumeManually = true
          } else if reason == .videoDeviceNotAvailableWithMultipleForegroundApps {
            canResumeManually = false
          }

          self.delegate?.sessionWasInterrupted(canResumeManually: canResumeManually)

        }
      }

      @objc func sessionInterruptionEnded(notification: Notification) {

        self.delegate?.sessionInterruptionEnded()
      }

      @objc func sessionRuntimeErrorOccured(notification: Notification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else {
          return
        }

        print("Capture session runtime error: \(error)")

        if error.code == .mediaServicesWereReset {
          sessionQueue.async {
            if self.isSessionRunning {
              self.startSession()
            } else {
              DispatchQueue.main.async {
                self.delegate?.sessionRunTimeErrorOccured()
              }
            }
          }
        } else {
          self.delegate?.sessionRunTimeErrorOccured()

        }
    }
}

/**
 AVCaptureVideoDataOutputSampleBufferDelegate
 */
extension CameraFeedManager: AVCaptureVideoDataOutputSampleBufferDelegate {

  /** This method delegates the CVPixelBuffer of the frame seen by the camera currently.
   */
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

    // Converts the CMSampleBuffer to a CVPixelBuffer.
    let pixelBuffer: CVPixelBuffer? = CMSampleBufferGetImageBuffer(sampleBuffer)

    guard let imagePixelBuffer = pixelBuffer else {
      return
    }

    // Delegates the pixel buffer to the ViewController.
    delegate?.didOutput(pixelBuffer: imagePixelBuffer)
  }

}
