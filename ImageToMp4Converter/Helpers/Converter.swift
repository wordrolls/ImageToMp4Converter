//
//  Converter.swift
//  ImageToMp4Converter
//
//  Created by sudeep on 15/04/20.
//  Copyright © 2020 sudeep. All rights reserved.
//

import Cocoa
import AVFoundation
import CoreGraphics

protocol ConverterDelegate: class
{
  func converter(willStart converter: Converter)
  func converter(_ converter: Converter, failedWithError error: Error?)
  func converter(didFinish converter: Converter)
}

// https://github.com/caferrara/img-to-video
class Converter: NSObject
{
  var inputUrl: URL
  var outputUrl: URL
  weak var delegate: ConverterDelegate?
  
  typealias SuccessBlock = () -> Void
  
  init(inputUrl: URL, outputUrl: URL)
  {
    self.inputUrl = inputUrl
    self.outputUrl = outputUrl
  }
  
  public func convert()
  {
    // callback
    delegate?.converter(willStart: self)
    
    // step 1
    if deleteExistingOutputFileIfNeeded() == true
    {
      // step 2
      writeVideo {
        
        // step 3
        self.exportVideo()
      }
    }
  }
}

// MARK: Delete existing

extension Converter
{
  private func deleteExistingOutputFileIfNeeded() -> Bool
  {
    let fileManager = FileManager.default
    let outputPath = outputUrl.path
    
    if fileManager.fileExists(atPath: outputPath) == false {
      return true
    }
    
    do {
      try fileManager.removeItem(atPath: outputPath)
    }
    catch
    {
      delegate?.converter(self, failedWithError: error)
      return false
    }
    
    return true
  }
}

// MARK: Write video

extension Converter
{
  private func writeVideo(_ completion: @escaping SuccessBlock)
  {
    var imageArray: [NSImage] = []
    var imageSize: NSSize?
    for _ in 1...2
    {
      let image = NSImage(contentsOf: inputUrl)!
      imageSize = image.size
      imageArray.append(image)
    }
    
    var writer: AVAssetWriter?
    do {
      writer = try AVAssetWriter(outputURL: outputUrl, fileType: AVFileType.mp4)
    }
    catch
    {
      delegate?.converter(self, failedWithError: error)
      return
    }
    
    let settings: [String : Any] = [
      AVVideoCodecKey: AVVideoCodecH264,
      AVVideoWidthKey: NSNumber(value: Float(imageSize!.width)),
      AVVideoHeightKey: NSNumber(value: Float(imageSize!.height))
    ]
    
    let writerInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: settings)
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput, sourcePixelBufferAttributes: nil)
    
    writerInput.expectsMediaDataInRealTime = true
    writer?.add(writerInput)
    writer?.startWriting()
    writer?.startSession(atSourceTime: CMTime.zero)
    
    var frameCount = 0
    let fps = 30
    let numberOfSecondsPerFrame = 1
    let frameDuration = fps * numberOfSecondsPerFrame
    
    for image in imageArray
    {
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
      guard let buffer = makePixelBuffer(cgImage) else { return }
      
      var appended = false
      var i = 0
      while (!appended && i < fps)
      {
        if adaptor.assetWriterInput.isReadyForMoreMediaData == true
        {
          let frameTime = CMTime(value: CMTimeValue(frameCount * frameDuration), timescale: CMTimeScale(fps))
          appended = adaptor.append(buffer, withPresentationTime: frameTime)
          
          if appended == false
          {
            delegate?.converter(self, failedWithError: writer!.error)
            return
          }
        }
        else
        {
          // adaptor not read; wait for a moment
          Thread.sleep(forTimeInterval: 0.1)
        }
        i += 1;
      }
      
      if appended == false
      {
        let error = NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Error appending image \(frameCount) times \(i)."])
        delegate?.converter(self, failedWithError: error)
        return
      }
      frameCount += 1;
    }
    
    // finish writing
    writerInput.markAsFinished()
    writer?.finishWriting {
      completion()
    }
  }
  
  private func makePixelBuffer(_ cgImage: CGImage) -> CVPixelBuffer?
  {
    let size = CGSize(width: cgImage.width, height: cgImage.height)
    let options = [
      kCVPixelBufferCGImageCompatibilityKey: NSNumber(value: true),
      kCVPixelBufferCGBitmapContextCompatibilityKey: NSNumber(value: true)
      ] as CFDictionary
    
    var buffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, options, &buffer)
    if status != kCVReturnSuccess
    {
      let error = NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unable to create pixel buffer."])
      delegate?.converter(self, failedWithError: error)
      return nil
    }
    
    CVPixelBufferLockBaseAddress(buffer!, CVPixelBufferLockFlags(rawValue: 0))
    let data = CVPixelBufferGetBaseAddress(buffer!)
    
    let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
    
    // https://stackoverflow.com/a/48304021
    let context = CGContext(data: data,
                            width: Int(size.width),
                            height: Int(size.height),
                            bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer!),
                            space: rgbColorSpace,
                            bitmapInfo: bitmapInfo.rawValue)
    
    context!.concatenate(CGAffineTransform(rotationAngle: 0))
    context!.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
    CVPixelBufferUnlockBaseAddress(buffer!, CVPixelBufferLockFlags(rawValue: 0))
    
    return buffer!
  }
}

// MARK: Export video

extension Converter
{
  private func exportVideo()
  {
    let asset = AVURLAsset(url: outputUrl)
    let timeRange = CMTimeRange(start: CMTime.zero, duration: asset.duration)
    
    let composition = AVMutableComposition()
    let videoTrack = composition.addMutableTrack(withMediaType: AVMediaType.video, preferredTrackID: kCMPersistentTrackID_Invalid)
    
    do
    {
      print(asset.tracks)
      try videoTrack?.insertTimeRange(timeRange, of: asset.tracks(withMediaType: AVMediaType.video).first!, at: CMTime.zero)
    }
    catch {
      delegate?.converter(self, failedWithError: error)
      return
    }
    
    let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
    exportSession?.outputFileType = AVFileType.mp4
    exportSession?.outputURL = outputUrl
    
    exportSession?.exportAsynchronously {
      self.delegate?.converter(didFinish: self)
    }
  }
}
