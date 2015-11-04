//
//  MBEViewController.m
//  Mipmapping
//
//  Created by Warren Moore on 12/8/14.
//  Copyright (c) 2014 Metal By Example. All rights reserved.
//------------------------------------------------------------------------
//  converted to Swift by Jamnitzer (Jim Wrenholt)
//------------------------------------------------------------------------
import UIKit
import Metal
import simd
import Accelerate

//------------------------------------------------------------------------------
class MBJViewController : UIViewController
{
    var metalView:MBJMetalView! = nil
    var renderer:MBJRenderer! = nil
    var displayLink:CADisplayLink! = nil
    
    var baseZoomFactor:Float = 0.0
    var pinchZoomFactor:Float = 0.0
    
    //------------------------------------------------------------------------
    override func viewDidLoad()
    {
        super.viewDidLoad()

        self.metalView = self.view as? MBJMetalView

        self.baseZoomFactor = 2
        self.pinchZoomFactor = 1
       
        self.renderer = MBJRenderer(layer: self.metalView.metalLayer)
        
        self.displayLink = CADisplayLink(target: self,
                selector: Selector("displayLinkDidFire:"))
        displayLink.addToRunLoop(NSRunLoop.mainRunLoop(),
                forMode: NSRunLoopCommonModes)
        
        let pinchGesture = UIPinchGestureRecognizer(target: self,
                action: "pinchGestureDidRecognize:")
        self.view.addGestureRecognizer(pinchGesture)
        
        let tapGesture = UITapGestureRecognizer(target: self,
                action: "tapGestureDidRecognize:")
        self.view.addGestureRecognizer(tapGesture)
    }
    //------------------------------------------------------------------------
    override func prefersStatusBarHidden() -> Bool
    {
        return true
    }
    //------------------------------------------------------------------------
    func displayLinkDidFire(sender:CADisplayLink)
    {
        self.renderer.cameraDistance = self.baseZoomFactor * self.pinchZoomFactor
//        print("self.renderer.cameraDistance \(self.renderer.cameraDistance) ")
        
        self.renderer.draw()
    }
    //------------------------------------------------------------------------
    func pinchGestureDidRecognize(gesture: UIPinchGestureRecognizer)
    {
        switch (gesture.state)
        {
        case UIGestureRecognizerState.Changed:
            self.pinchZoomFactor = Float(1.0) / Float(gesture.scale)
            break
        case UIGestureRecognizerState.Ended:
            self.baseZoomFactor = self.baseZoomFactor * self.pinchZoomFactor
            self.pinchZoomFactor = 1.0
        default:
            break
        }
        
        let constrainedZoom:Float = fmax(1.0, fmin(100.0,
                self.baseZoomFactor * self.pinchZoomFactor))
        self.pinchZoomFactor = constrainedZoom / self.baseZoomFactor
    }
    //------------------------------------------------------------------------
    func tapGestureDidRecognize(recognize: UITapGestureRecognizer)
    {
        var mipmap_num:UInt = UInt(self.renderer.mipmappingMode.rawValue)
        mipmap_num = (mipmap_num + 1) % 4
        print("mipmap_num \(mipmap_num) ")
        
       self.renderer.mipmappingMode = MIPMAP_MODE(rawValue:mipmap_num)!
    }
    //------------------------------------------------------------------------
}
