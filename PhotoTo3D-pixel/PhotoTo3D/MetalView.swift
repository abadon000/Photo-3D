//
//  MetalView.swift
//  PhotoTo3D
//
//  Created by lcy on 2022/6/15.
//  Copyright © 2022 admin. All rights reserved.
//

import UIKit
import Metal
import MetalKit
import GLKit

class MetalView: UIView {
    
    struct Uniforms {
        var pointTexcoordScaleX: Float!
        var pointTexcoordScaleY: Float!
        var pointSizeInPixel: Float!

        func data() -> [Float] {
            return [pointTexcoordScaleX, pointTexcoordScaleY, pointSizeInPixel]
        }

        static func sizeInBytes() -> Int {
            return 3 * MemoryLayout<Float>.size
        }
    }
    
    
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var pipelineState: MTLRenderPipelineState!
    var pipelineStateDescriptor: MTLRenderPipelineDescriptor!
    
    var metalLayer: CAMetalLayer!
    var vertexData:[Float]!
    var indexData:[UInt32]!
    var uniforms: Uniforms!
    
    var centerX: Float! = 0.0
    var centerY: Float! = 0.0
    var degree: Float! = 60.0
    
    var image:UIImage!
    var imageWidth: Float!
    var imageHeight: Float!
    var imageTexture: MTLTexture!
    
    var type: MTLPrimitiveType = .triangle
    var drawValue: Float = 5.0

    override func awakeFromNib() {
        super.awakeFromNib()
        image = UIImage.init(named: "child.jpeg")
        initMetal()
        initPipeline()
    }
    
    func syncFrame() {
        self.metalLayer.frame = self.bounds
    }
    
    func getTexture() {
        do {
            self.imageTexture = try MTKTextureLoader(device: self.device).newTexture(cgImage: image.cgImage!, options: [MTKTextureLoader.Option.SRGB:false])
        } catch {
            assertionFailure("Could not create Texture - \(error) ")
        }
        render(texture: imageTexture)
    }
    
    func initMetal() {
        device = MTLCreateSystemDefaultDevice()
        guard device != nil else {
            print("Metal is not supported on this device")
            return
        }
        metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.frame = self.bounds
        self.layer.addSublayer(metalLayer)
    }
    
    func initPipeline() {
        
        imageWidth = Float(image.size.width)
        imageHeight = Float(image.size.height)
        
        commandQueue = device.makeCommandQueue()
        
        let library = device.makeDefaultLibrary()!
        let fragmentFunc = library.makeFunction(name: "fragment_func")!
        let vertexFunc = library.makeFunction(name: "vertex_func")!
        
        self.pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.vertexFunction = vertexFunc
        pipelineStateDescriptor.fragmentFunction = fragmentFunc
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = metalLayer.pixelFormat
        
        do {
            try pipelineState = device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
        } catch let error {
            print("Failed to create pipeline state, error \(error)")
        }
        
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(pan))
        self.addGestureRecognizer(panGesture)
        
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(pinch))
        self.addGestureRecognizer(pinchGesture)
    }
    
    func glkToSimd(mat: GLKMatrix4)-> matrix_float4x4{
        let res = matrix_float4x4.init(columns: (
            simd_make_float4(mat.m00, mat.m01, mat.m02, mat.m03),
            simd_make_float4(mat.m10, mat.m11, mat.m12, mat.m13),
            simd_make_float4(mat.m20, mat.m21, mat.m22, mat.m23),
            simd_make_float4(mat.m30, mat.m31, mat.m32, mat.m33)
           ))
        return res
    }
    
    func createTexture(image: UIImage) -> MTLTexture? {
        let bitsPerComponent = 8
        let bytesPerPixel = 4
        let width:Int = Int(image.size.width)
        let height:Int = Int(image.size.height)
        let imageData = UnsafeMutableRawPointer.allocate(byteCount: Int(width * height * bytesPerPixel), alignment: 8)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let imageContext = CGContext.init(data: imageData, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: width * bytesPerPixel, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGImageByteOrderInfo.order32Big.rawValue )
        UIGraphicsPushContext(imageContext!)
        imageContext?.translateBy(x: 0, y: CGFloat(height))
        imageContext?.scaleBy(x: 1, y: -1)
        image.draw(in: CGRect.init(x: 0, y: 0, width: width, height: height))
        UIGraphicsPopContext()
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: imageData, bytesPerRow: width * bytesPerPixel)
        return texture
        
    }
    
    func render(texture: MTLTexture) {
        guard let drawable = metalLayer?.nextDrawable() else { return }
        let renderPassDescriptor = MTLRenderPassDescriptor.init()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor.init(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0);
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        renderEncoder.pushDebugGroup("begin draw")
        renderEncoder.setRenderPipelineState(pipelineState)
        
        self.draw(renderEncoder: renderEncoder, texture: texture, type: type)
        
        renderEncoder.popDebugGroup()
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    func draw(renderEncoder: MTLRenderCommandEncoder, texture: MTLTexture, type: MTLPrimitiveType) {
        self.uniforms = Uniforms.init()
        self.vertexData = buildPointData()
        self.indexData = buildIndexData()
        
        let vertexBufferSize = MemoryLayout<Float>.stride * self.vertexData.count
        let indexBufferSize = MemoryLayout<UInt32>.stride * self.indexData.count
        let vertexBuffer = device.makeBuffer(bytes: self.vertexData, length: vertexBufferSize, options: MTLResourceOptions.cpuCacheModeWriteCombined)
        let indexBuffer = device.makeBuffer(bytes: self.indexData, length: indexBufferSize , options: MTLResourceOptions.cpuCacheModeWriteCombined)
        
        let aspect = self.bounds.width / self.bounds.height

        let GLKPerspective = GLKMatrix4MakePerspective(GLKMathDegreesToRadians(degree), Float(aspect), 0.1, 10.0)
        let GLKView = GLKMatrix4MakeLookAt(0.0, 0.0, 2.0, 0, 0, 0.0, 0.0, 1.0, 0.0)

        var GLKModel = GLKMatrix4Translate(GLKMatrix4Identity, 0.0, 0.0, 0.0)
        GLKModel = GLKMatrix4Rotate(GLKModel, centerX, 1, 0, 0)
        GLKModel = GLKMatrix4Rotate(GLKModel, centerY, 0, 1, 0)
        
        var perspective = glkToSimd(mat: GLKPerspective)
        var view = glkToSimd(mat: GLKView)
        var model = glkToSimd(mat: GLKModel)
                              
        let perspectiveBuffer = device.makeBuffer(bytes: &perspective, length: MemoryLayout<float4x4>.size, options: .cpuCacheModeWriteCombined)
        let viewBuffer = device.makeBuffer(bytes: &view, length: MemoryLayout<float4x4>.size, options: .cpuCacheModeWriteCombined)
        let modelBuffer = device.makeBuffer(bytes: &model, length: MemoryLayout<float4x4>.size, options: .cpuCacheModeWriteCombined)
        
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(modelBuffer, offset: 0, index: 1)
        renderEncoder.setVertexBuffer(viewBuffer, offset: 0, index: 2)
        renderEncoder.setVertexBuffer(perspectiveBuffer, offset: 0, index: 3)
        let uniformBuffer = device.makeBuffer(bytes: self.uniforms.data(), length: Uniforms.sizeInBytes(), options: MTLResourceOptions.cpuCacheModeWriteCombined)
        renderEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 4)
        renderEncoder.setFragmentTexture(texture, index: 0)
        renderEncoder.setVertexTexture(texture, index: 0)

        if type == .point {
            renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: self.vertexData.count / 6)
        } else if type == .triangle {
            renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: self.indexData.count, indexType: MTLIndexType.uint32, indexBuffer: indexBuffer!, indexBufferOffset: 0)
        } else {
            renderEncoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: self.vertexData.count / 6)
        }
    }
    
    @objc func pan(_ gesture: UIPanGestureRecognizer) {
        let move = gesture.translation(in: self)
        centerY += 0.8 * Float(move.x) / imageWidth
        centerX += 0.8 * Float(move.y) / imageHeight
        render(texture: imageTexture)
    }
    
    
    @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
        let move = gesture.scale
        degree /= Float(move)
        if degree > 160.0 {
            degree = 160
        }
        if degree < 20 {
            degree = 20
        }
        render(texture: imageTexture)
        gesture.scale = 1.0
    }
    
    func buildPointData() -> [Float] {
        var vertexDataArray: [Float] = []
        let pointSize = drawValue
        let rowCount = Int(imageHeight / pointSize) + 1
        let colCount = Int(imageWidth / pointSize) + 1
        let sizeXInMetalTexcoord: Float = pointSize / imageWidth * 2.0
        let sizeYInMetalTexcoord: Float = pointSize / imageHeight * 2.0
        if type == .point {
            for row in stride(from: 0, to: rowCount, by: Int(drawValue)) {
                for col in stride(from: 0, to: colCount, by: 4) {
                    let xCoord = Float(col) * sizeXInMetalTexcoord + sizeXInMetalTexcoord / 2.0 - 1.0
                    let yCoord = 1.0 - Float(row) * sizeYInMetalTexcoord - sizeYInMetalTexcoord / 2.0
                    vertexDataArray.append(xCoord)
                    vertexDataArray.append(yCoord)
                    vertexDataArray.append(0.0)
                    vertexDataArray.append(1.0)
                    vertexDataArray.append(Float(col) / Float(colCount))
                    vertexDataArray.append(Float(row) / Float(rowCount))
                }
            }
        } else {
            for row in 0 ..< rowCount {
                for col in 0 ..< colCount {
                    let centerX = Float(col) * sizeXInMetalTexcoord + sizeXInMetalTexcoord / 2.0 - 1.0
                    let centerY = 1.0 - Float(row) * sizeYInMetalTexcoord - sizeYInMetalTexcoord / 2.0
                    vertexDataArray.append(centerX)
                    vertexDataArray.append(centerY)
                    vertexDataArray.append(0.0)
                    vertexDataArray.append(1.0)
                    vertexDataArray.append(Float(col) / Float(colCount))
                    vertexDataArray.append(Float(row) / Float(rowCount))
                }
            }
        }
        uniforms.pointTexcoordScaleX = sizeXInMetalTexcoord / 2.0
        uniforms.pointTexcoordScaleY = sizeYInMetalTexcoord / 2.0
        uniforms.pointSizeInPixel = pointSize
        return vertexDataArray
    }

    func buildIndexData() -> [UInt32] {
        var indexDataArray: [UInt32] = []
        let pointSize = drawValue
        let rowCount = UInt32(imageHeight / pointSize) + 1
        let colCount = UInt32(imageWidth / pointSize) + 1
        for row in 0 ..< rowCount-1 {
            for col in 0 ..< colCount-1 {
                indexDataArray.append(colCount * row + col)
                indexDataArray.append(colCount * row + col + 1)
                indexDataArray.append(colCount * (row + 1) + col)
                indexDataArray.append(colCount * (row + 1) + col)
                indexDataArray.append(colCount * row + col + 1)
                indexDataArray.append(colCount * (row + 1) + col + 1)
            }
        }
        return indexDataArray
    }
        

}
