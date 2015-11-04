//
//  MBETextureGenerator.m
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
import Accelerate

//------------------------------------------------------------------------------
class MBJTextureGenerator
{
    //------------------------------------------------------------------------------
    // Generates a square checkerboard texture with the specified number of tiles.
    // If `colorfulMipmaps` is YES, mipmap levels will be generated on the CPU
    // and tinted to be visually distinct when drawn.
    // Otherwise, the blit command encoder is used to
    // generate all mipmap levels on the GPU.
    //------------------------------------------------------------------------------
    class func checkerboardTextureWithSize( size:CGSize, tileCount:Int,
                colorfulMipmaps:Bool, device:MTLDevice, completionBlock: (MTLTexture) -> Void)
    {
        let bytesPerPixel:Int = 4
        let bytesPerRow:Int = bytesPerPixel * Int(size.width)
        
        let descriptor =
        MTLTextureDescriptor.texture2DDescriptorWithPixelFormat( .RGBA8Unorm,
            width: Int(size.width), height: Int(size.height),
            mipmapped: true)
        
        let texture = device.newTextureWithDescriptor(descriptor)
        texture.label = "checkerboard texture"

        var baseLevelData:NSData
        var image:CGImage
        
        (baseLevelData, image) = createCheckerboardImageDataWithSize(size,
                tileCount:tileCount)
        
        let region = MTLRegionMake2D(0, 0, Int(size.width), Int(size.height))
        texture.replaceRegion(region, mipmapLevel: 0,
            withBytes: baseLevelData.bytes, bytesPerRow: bytesPerRow)
        
         if (colorfulMipmaps)
         {
            texture.label = "tinted checkerboard texture"
            image = generateTintedMipmapsForTexture(texture,
                    image:image, completionBlock:completionBlock)
         }
         else
         {
            texture.label = "accel checkerboard texture"
            generateMipmapsAcceleratedForTexture(texture,
                    device:device, completionBlock:completionBlock)
        }
    }
    //------------------------------------------------------------------------------
    class func createCheckerboardImageDataWithSize(
                    size:CGSize, tileCount:Int) -> (NSData, CGImage)
    {
        let width:Int = Int(size.width)
        let height:Int = Int(size.height)
        
         if ((width % tileCount != 0) || (height % tileCount != 0))
         {
            print("Texture generator was asked for a checkerboard image with non-whole tile sizes: ")
            print("size is \(width) X \(height), but tileCount is \(tileCount)")
            print("which doesn't divide evenly. The resulting image will have gaps.")
         }
        
        let bytesPerPixel:Int = 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        let dataLength:Int = height * width * bytesPerPixel
        let data = calloc(dataLength, sizeof(UInt8))
        
        let bytesPerRow:Int = bytesPerPixel * width
        let bitsPerComponent:Int = 8
        
        let options = CGImageAlphaInfo.PremultipliedLast.rawValue |
            CGBitmapInfo.ByteOrder32Big.rawValue
        
        let context:CGContextRef = CGBitmapContextCreate(data, width, height,
            bitsPerComponent, bytesPerRow, colorSpace, options)!
        // CGColorSpaceRelease(colorSpace)
        
        // Flip the context so the positive Y axis points down
        CGContextTranslateCTM(context, 0.0, CGFloat(height))
        CGContextScaleCTM(context, 1.0, -1.0)
        
        let lightValue:CGFloat = 0.95
        let darkValue:CGFloat = 0.15
        let tileWidth:Int = Int(width) / tileCount
        let tileHeight:Int = Int(height) / tileCount
        
        for (var r:Int = 0; r < tileCount; ++r)
        {
            var useLightColor:Bool = (r % 2 == 0)
            for (var c:Int = 0; c < tileCount; ++c)
            {
                let value:CGFloat = useLightColor ? lightValue : darkValue
                CGContextSetRGBFillColor(context, value, value, value, 1.0)
                CGContextFillRect(context, CGRectMake(
                    CGFloat(r * tileHeight), CGFloat(c * tileWidth),
                    CGFloat(tileWidth), CGFloat(tileHeight)))
                useLightColor = !useLightColor
            }
        }
        let outImage = CGBitmapContextCreateImage(context)
        
        // CGContextRelease(context)
        let nsdata = NSData(bytesNoCopy:data,
            length:dataLength,
            freeWhenDone:true)
        
        return (nsdata, outImage!)
    }
    //------------------------------------------------------------------------------
    class func generateTintedMipmapsForTexture(
            texture:MTLTexture,
            image:CGImage,
            completionBlock: (MTLTexture) -> Void ) -> CGImage
    {
        let bytesPerPixel:Int = 4

        var level:Int = 1
        var mipWidth:Int = texture.width / 2
        var mipHeight:Int = texture.height / 2
        var scaledImage:CGImage
        // CGImageRetain(image)
        var outImage = image
        
        while (mipWidth >= 1 && mipHeight >= 1)
        {
            let mipBytesPerRow:Int = bytesPerPixel * mipWidth
            let tintColor:UIColor = tintColorAtIndex(level - 1)
            
            var mipData:NSData
            (mipData, scaledImage) = createResizedImageDataForImage(image,
                size:CGSizeMake( CGFloat(mipWidth), CGFloat(mipHeight)), tintColor:tintColor)
            
            // CGImageRelease(image)
            outImage = scaledImage
            
            let region = MTLRegionMake2D(0, 0, Int(mipWidth), Int(mipHeight))
            texture.replaceRegion(region, mipmapLevel: level,
                withBytes: mipData.bytes, bytesPerRow: Int(mipBytesPerRow))
            
            mipWidth /= 2
            mipHeight /= 2
            ++level
        }
        // CGImageRelease(image)
        
        completionBlock(texture)
        return outImage
    }
    //------------------------------------------------------------------------------
    class func generateMipmapsAcceleratedForTexture(texture:MTLTexture,
        device:MTLDevice, completionBlock: (MTLTexture) -> Void)
    {
        let commandQueue:MTLCommandQueue = device.newCommandQueue()
        let commandBuffer:MTLCommandBuffer = commandQueue.commandBuffer()
        let commandEncoder:MTLBlitCommandEncoder = commandBuffer.blitCommandEncoder()
        
        commandEncoder.generateMipmapsForTexture(texture)
        commandEncoder.endEncoding()
        commandBuffer.addCompletedHandler({  buffer in return completionBlock(texture)})
        commandBuffer.commit()
    }
    //------------------------------------------------------------------------------
    class func createResizedImageDataForImage(image:CGImage, size:CGSize,
                                    tintColor:UIColor) -> (NSData, CGImage)
    {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let dataLength:Int = Int(size.height) * Int(size.width) * 4
        
        let data = calloc(dataLength, sizeof(UInt8))
        
        let bytesPerPixel: Int = 4
        let bytesPerRow:Int = bytesPerPixel * Int(size.width)
        let bitsPerComponent: Int = 8
        
        let options = CGImageAlphaInfo.PremultipliedLast.rawValue |
            CGBitmapInfo.ByteOrder32Big.rawValue
        
        let context:CGContextRef = CGBitmapContextCreate(data,
            Int(size.width), Int(size.height),
            bitsPerComponent, bytesPerRow, colorSpace, options)!
        CGContextSetInterpolationQuality(context, .High)
        
        let targetRect:CGRect = CGRectMake(0, 0, size.width, size.height)
        CGContextDrawImage(context, targetRect, image)
        let outImage = CGBitmapContextCreateImage(context)
        
        var r:CGFloat = 0.0
        var g:CGFloat = 0.0
        var b:CGFloat = 0.0
        var a:CGFloat = 0.0
        tintColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        
        CGContextSetRGBFillColor(context, r, g, b, 1)
        CGContextSetBlendMode (context, .Multiply)
        CGContextFillRect (context, targetRect)
        
        // CFRelease(colorSpace)
        // CFRelease(context)
        
        let nsdata = NSData(bytesNoCopy:data,
            length:dataLength,
            freeWhenDone:true)
        
        return (nsdata, outImage!)
    }
    //------------------------------------------------------------------------------
    class func tintColorAtIndex(index:Int) -> UIColor
    {
        switch (index % 7)
        {
        case 0: return UIColor.redColor()
        case 1: return UIColor.orangeColor()
        case 2: return UIColor.yellowColor()
        case 3: return UIColor.greenColor()
        case 4: return UIColor.blueColor()
        case 5: return UIColor(red:0.5, green:0.0, blue:1.0, alpha:1.0) // indigo
        case 6: return UIColor.purpleColor()
        default: return UIColor.purpleColor()
        }
    }
    //------------------------------------------------------------------------------
}
//------------------------------------------------------------------------------
