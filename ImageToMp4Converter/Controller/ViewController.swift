//
//  ViewController.swift
//  ImageToMp4Converter
//
//  Created by sudeep on 15/04/20.
//  Copyright © 2020 sudeep. All rights reserved.
//

import Cocoa

class ViewController: NSViewController, ConverterDelegate
{
  @IBOutlet weak var inputPathLabel: NSTextField!
  @IBOutlet weak var convertButton: NSButton!
  var converter: Converter?
  var inputUrl: URL?
  var outputUrl: URL?
  
  override func viewDidLoad()
  {
    super.viewDidLoad()
    setup()
  }
  
  private func setup()
  {
    inputPathLabel.stringValue = ""
  }
  
  @IBAction func selectImageTapped(_ sender: Any)
  {
    let filePicker = NSOpenPanel()
    filePicker.canChooseFiles = true
    filePicker.allowedFileTypes = ["png", "jpg", "jpeg"]
    filePicker.allowsMultipleSelection = false
    
    if filePicker.runModal() == .OK {
      prepareImageForConversion(filePicker.url!)
    }
  }
  
  private func prepareImageForConversion(_ url: URL)
  {
    inputUrl = url
    outputUrl = inputUrl?.deletingPathExtension().appendingPathExtension("mp4")
    inputPathLabel.stringValue = inputUrl!.path
  }
  
  @IBAction func convertTapped(_ sender: Any)
  {
    startConversion()
  }
  
  private func startConversion()
  {
    converter = Converter(inputUrl: inputUrl!, outputUrl: outputUrl!)
    converter!.delegate = self
    converter!.convert()
  }
  
  // MARK: ConverterDelegate
  func converter(willStart converter: Converter)
  {
    convertButton.isEnabled = false
    convertButton.title = "Converting..."
  }
  
  func converter(_ converter: Converter, failedWithError error: Error?)
  {
    if let _ = error {
      showAlert("Error", error!.localizedDescription)
    }
    
    DispatchQueue.main.async {
      self.resetConvertButtonState()
    }
  }
  
  func converter(didFinish converter: Converter)
  {
    DispatchQueue.main.async {
      
      self.resetConvertButtonState()
      
    let alert = NSAlert.init()
    alert.messageText = "Yay!"
    alert.informativeText = "Video saved at \(self.outputUrl!.path)"
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Open file location")
    alert.beginSheetModal(for: self.view.window!) { (response) in
        
        if response == .alertSecondButtonReturn {
          NSWorkspace.shared.open(self.outputUrl!.deletingLastPathComponent())
        }
      }
    }
  }
  
  private func resetConvertButtonState()
  {
    convertButton.isEnabled = true
    convertButton.title = "Convert"
  }
}

extension ViewController
{
  private func showAlert(_ title: String, _ message: String)
  {
    let alert = NSAlert.init()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "OK")
    alert.beginSheetModal(for: view.window!, completionHandler: nil)
  }
}
