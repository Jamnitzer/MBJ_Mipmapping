//
//  MBERenderer.m
//  Mipmapping
//
//  Created by Warren Moore on 11/7/14.
//  Copyright (c) 2014 Metal By Example. All rights reserved.
//------------------------------------------------------------------------
//  converted to Swift by Jamnitzer (Jim Wrenholt)
//------------------------------------------------------------------------
import UIKit
import Metal
import simd
import QuartzCore

//------------------------------------------------------------------------------
enum MIPMAP_MODE:UInt {
    case MBJMipmappingMode_None,
    MBJMipmappingMode_BlitGeneratedLinear,
    MBJMipmappingMode_VibrantLinear,
    MBJMipmappingMode_VibrantNearest }

//------------------------------------------------------------------------------
class MBJRenderer
{
    //-------------------------------------------------------------------------
    var device:MTLDevice! = nil
    var layer:CAMetalLayer! = nil
    var cameraDistance:Float! = nil
    var mipmappingMode:MIPMAP_MODE = .MBJMipmappingMode_None
    
    let X = float3(1, 0, 0)
    let Y = float3(0, 1, 0)
    
    var commandQueue:MTLCommandQueue! = nil
    var library:MTLLibrary! = nil
    var pipeline:MTLRenderPipelineState? = nil
    var uniformBuffer:MTLBuffer! = nil
    var depthTexture:MTLTexture! = nil
    var checkerTexture:MTLTexture! = nil
    var vibrantCheckerTexture:MTLTexture! = nil
    var depthState:MTLDepthStencilState? = nil
    var notMipSamplerState:MTLSamplerState! = nil
    var nearestMipSamplerState:MTLSamplerState! = nil
    var linearMipSamplerState:MTLSamplerState! = nil
    var cube:MBJMesh! = nil
    var angleX:Float = 0.0
    var angleY:Float = 0.0
    
    //-------------------------------------------------------------------------
    init(layer:CAMetalLayer)
    {
        self.cameraDistance = 1
        self.mipmappingMode = .MBJMipmappingMode_VibrantLinear
        
        buildMetal()
        buildPipeline()
        buildResources()
        
        self.layer = layer
        self.layer.device = self.device
    }
    //-------------------------------------------------------------------------
    func buildMetal()
    {
        self.device = MTLCreateSystemDefaultDevice()
        commandQueue = device!.newCommandQueue()
        self.library =  self.device!.newDefaultLibrary()
    }
    //-------------------------------------------------------------------------
    func buildPipeline()
    {
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].format = MTLVertexFormat.Float4
        
        vertexDescriptor.attributes[1].offset = sizeof(float4)
        vertexDescriptor.attributes[1].format = MTLVertexFormat.Float4
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunction.PerVertex
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stride = sizeof(MBJVertex)
        
        print("sizeof(MBJVertex) = \(sizeof(MBJVertex)) ")
        
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = self.library.newFunctionWithName("vertex_project")
        pipelineDescriptor.fragmentFunction = self.library.newFunctionWithName("fragment_texture")
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormat.BGRA8Unorm
        pipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormat.Depth32Float
        
        do {
            self.pipeline = try
                device.newRenderPipelineStateWithDescriptor(pipelineDescriptor)
        }
        catch let pipelineError as NSError
        {
            self.pipeline = nil
            print("Error occurred when creating render pipeline state \(pipelineError)")
            assert(false)
        }
        
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = MTLCompareFunction.Less
        depthDescriptor.depthWriteEnabled = true
        self.depthState = device!.newDepthStencilStateWithDescriptor(depthDescriptor)
        
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = MTLSamplerMinMagFilter.Linear
        samplerDescriptor.magFilter = MTLSamplerMinMagFilter.Linear
        samplerDescriptor.sAddressMode = MTLSamplerAddressMode.ClampToEdge
        samplerDescriptor.tAddressMode = MTLSamplerAddressMode.ClampToEdge
        
        samplerDescriptor.mipFilter = MTLSamplerMipFilter.NotMipmapped
        self.notMipSamplerState = self.device!.newSamplerStateWithDescriptor(samplerDescriptor)
        
        samplerDescriptor.mipFilter = MTLSamplerMipFilter.Nearest
        self.nearestMipSamplerState = self.device!.newSamplerStateWithDescriptor(samplerDescriptor)
        
        samplerDescriptor.mipFilter = MTLSamplerMipFilter.Linear
        self.linearMipSamplerState = self.device!.newSamplerStateWithDescriptor(samplerDescriptor)
    }
    //-------------------------------------------------------------------------
    func buildResources()
    {
        self.cube = MBJCubeMesh(device:self.device)
        let textureSize:CGSize = CGSizeMake(512.0, 512.0)
        let tileCount:Int = 8
        
        MBJTextureGenerator.checkerboardTextureWithSize(textureSize,
            tileCount:tileCount,
            colorfulMipmaps:false,
            device:self.device,
            completionBlock: { (texture:MTLTexture) in self.checkerTexture = texture } )
        
        MBJTextureGenerator.checkerboardTextureWithSize(textureSize,
            tileCount:tileCount,
            colorfulMipmaps:true,
            device:self.device,
            completionBlock: { (texture:MTLTexture) in self.vibrantCheckerTexture = texture } )
        
        let uniforms_size = sizeof(Float) * (16 + 16 + 12)
        self.uniformBuffer = self.device.newBufferWithLength(uniforms_size,
            options:.CPUCacheModeDefaultCache)
        
        self.uniformBuffer.label = "uniformBuffer"
    }
    //-------------------------------------------------------------------------
    func buildDepthBuffer()
    {
        let drawableSize:CGSize = self.layer.drawableSize
        
        let depthTexDesc =
        MTLTextureDescriptor.texture2DDescriptorWithPixelFormat( .Depth32Float,
            width: Int(drawableSize.width), height: Int(drawableSize.height),
            mipmapped: false)
        
        self.depthTexture = self.device.newTextureWithDescriptor(depthTexDesc)
        self.depthTexture.label = "depthTexture"
    }
    //-------------------------------------------------------------------------
    func drawSceneWithCommandEncoder(commandEncoder:MTLRenderCommandEncoder)
    {
        var texture:MTLTexture! = nil
        var sampler:MTLSamplerState! = nil
        
        switch (self.mipmappingMode)
        {
        case .MBJMipmappingMode_None:
            texture = self.checkerTexture
            sampler = self.notMipSamplerState
        case .MBJMipmappingMode_BlitGeneratedLinear:
            texture = self.checkerTexture
            sampler = self.linearMipSamplerState
        case .MBJMipmappingMode_VibrantNearest:
            texture = self.vibrantCheckerTexture
            sampler = self.nearestMipSamplerState
        case .MBJMipmappingMode_VibrantLinear:
            texture = self.vibrantCheckerTexture
            sampler = self.linearMipSamplerState
        }
        
        commandEncoder.setRenderPipelineState(self.pipeline!)
        commandEncoder.setDepthStencilState( self.depthState!)
        commandEncoder.setFragmentTexture( texture, atIndex: 0)
        commandEncoder.setFragmentSamplerState( sampler, atIndex: 0)
        
        commandEncoder.setVertexBuffer( self.cube.vertexBuffer, offset: 0, atIndex: 0)
        commandEncoder.setVertexBuffer( self.uniformBuffer, offset: 0, atIndex: 1)
        
        commandEncoder.drawIndexedPrimitives( .Triangle,
            indexCount:self.cube.indexBuffer.length / sizeof(MBJIndexType),
            indexType:MTLIndexType.UInt16,
            indexBuffer:self.cube.indexBuffer,
            indexBufferOffset:0)
    }
    //-------------------------------------------------------------------------
    func renderPassForDrawable(drawable:CAMetalDrawable) -> MTLRenderPassDescriptor
    {
        let renderPass = MTLRenderPassDescriptor()
        
        renderPass.colorAttachments[0].texture = drawable.texture
        renderPass.colorAttachments[0].loadAction = MTLLoadAction.Clear
        renderPass.colorAttachments[0].storeAction = MTLStoreAction.Store
        renderPass.colorAttachments[0].clearColor = MTLClearColorMake(1, 1, 1, 1)
        
        renderPass.depthAttachment.texture = self.depthTexture
        renderPass.depthAttachment.loadAction = MTLLoadAction.Clear
        renderPass.depthAttachment.storeAction = MTLStoreAction.DontCare
        renderPass.depthAttachment.clearDepth = 1
        
        return renderPass
    }
    //-------------------------------------------------------------------------
    func updateUniforms()
    {
        let size:CGSize = self.layer.bounds.size
        let aspectRatio:Float = Float(size.width / size.height)
        let verticalFOV:Float = (aspectRatio > 1) ? Float(M_PI / 3) : Float(M_PI / 2)
        let near:Float = 0.1
        let far:Float = 100.0
        let projectionMatrix:float4x4 = matrix_perspective_projection(aspectRatio,
            fovy: verticalFOV, near: near, far: far)
        
        let cameraPosition = float4(0.0, 0.0, -self.cameraDistance, 1.0)
        let viewMatrix:float4x4 = matrix_translation(cameraPosition)
        
        let cubePosition:float4 = float4(0, 0, 0, 1)
        let cube_rotX:float4x4 = matrix_rotation(X, angle:self.angleX)
        let cube_rotY:float4x4 = matrix_rotation(Y, angle:self.angleY)
        let cube_rotXY:float4x4 = cube_rotX * cube_rotY
        let cube_trans:float4x4 = matrix_translation(cubePosition)
        let cubeModelMatrix:float4x4 = cube_trans * cube_rotXY
        
        var uniforms = MBJUniforms()
        let uniforms_size = sizeof(Float) * (16 + 16 + 12)
        
        uniforms.modelMatrix = cubeModelMatrix
        
        let cubeMM3:float3x3 = matrix_upper_left3x3(cubeModelMatrix)
        uniforms.normalMatrix = cubeMM3.inverse
        
        let mv:float4x4 = viewMatrix * cubeModelMatrix
        let mvp:float4x4 = projectionMatrix * mv
        uniforms.modelViewProjectionMatrix = mvp
        
        memcpy(self.uniformBuffer.contents(), &uniforms, uniforms_size)
        
        self.angleY += 0.01
        self.angleX += 0.015
    }
    //-------------------------------------------------------------------------
    func draw()
    {
        let drawableSize:CGSize = self.layer.drawableSize
        
        if (self.depthTexture == nil )
        {
            buildDepthBuffer()
        }
        
        if (CGFloat(self.depthTexture.width) != drawableSize.width ||
            CGFloat(self.depthTexture.height) != drawableSize.height)
        {
            buildDepthBuffer()
        }
        
        let drawable:CAMetalDrawable? = self.layer.nextDrawable()
        if (drawable != nil)
        {
            updateUniforms()
            
            let commandBuffer:MTLCommandBuffer = commandQueue.commandBuffer()
            let renderPass:MTLRenderPassDescriptor = renderPassForDrawable(drawable!)
            
            let commandEncoder:MTLRenderCommandEncoder =
            commandBuffer.renderCommandEncoderWithDescriptor(renderPass)
            commandEncoder.setCullMode( MTLCullMode.Back)
            commandEncoder.setFrontFacingWinding(MTLWinding.CounterClockwise)
            
            drawSceneWithCommandEncoder(commandEncoder)
            
            commandEncoder.endEncoding()
            commandBuffer.presentDrawable(drawable!)
            commandBuffer.commit()
        }
    }
    //-------------------------------------------------------------------------
}
//------------------------------------------------------------------------------
