//
//  ViewController.swift
//  PhotoTo3D
//
//  Created by lcy on 2022/6/12.
//  Copyright © 2022 admin. All rights reserved.
//

import UIKit

class ViewController: UIViewController, UIImagePickerControllerDelegate,  UINavigationControllerDelegate {
    
    var imagePickerController: UIImagePickerController!
    
    @IBOutlet weak var metalView: MetalView!
    @IBOutlet weak var slider: UISlider!
    @IBOutlet weak var typeSelect: UISegmentedControl!
    @IBAction func selectPic(_ sender: Any) {
        self.imagePickerController = UIImagePickerController()
        self.imagePickerController.delegate = self
        self.imagePickerController.allowsEditing = true
        self.imagePickerController.sourceType = UIImagePickerController.SourceType.photoLibrary
        self.present(self.imagePickerController, animated: true, completion: nil)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        let image:UIImage? = info[UIImagePickerController.InfoKey.originalImage] as? UIImage;
        let imageData = image?.jpegData(compressionQuality: 0.4)
        self.metalView.image = UIImage(data: imageData!)
        self.metalView.getTexture()
        self.dismiss(animated: true, completion: nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = UIColor.init(white: 0.85, alpha: 1.0)
        if let image = UIImage.init(named: "child.jpeg") {
            self.metalView.getTexture()
        }
        self.typeSelect.addTarget(self, action: #selector(changeStyle), for: .valueChanged)
        self.typeSelect.selectedSegmentIndex = 0
        slider.addTarget(self, action: #selector(setDrawValue), for: .valueChanged)
    }
        
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        metalView.syncFrame()
    }
    
    @objc func changeStyle(sender: UISegmentedControl) {
        if sender.selectedSegmentIndex == 0 {
            metalView.type = .triangle
        } else if sender.selectedSegmentIndex == 1 {
            metalView.type = .point
        } else {
            metalView.type = .lineStrip
        }
        self.metalView.getTexture()
    }
    
    @objc func setDrawValue(sender: UISlider) {
        if metalView.type == .point {
            metalView.drawValue = sender.value
            self.metalView.getTexture()
        }
        if metalView.type == .lineStrip {
            metalView.drawValue = sender.value * 2
            self.metalView.getTexture()
        }
    }
    
}
