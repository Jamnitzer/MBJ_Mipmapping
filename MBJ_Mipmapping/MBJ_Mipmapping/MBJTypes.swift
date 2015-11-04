//
//  MBETypes.h
//  Mipmapping
//
//  Created by Warren Moore on 11/10/14.
//  Copyright (c) 2014 Metal By Example. All rights reserved.
//------------------------------------------------------------------------
//  converted to Swift by Jamnitzer (Jim Wrenholt)
//------------------------------------------------------------------------
import UIKit
import Metal
import simd
import Accelerate

//------------------------------------------------------------------------------
struct MBJUniforms
{
    var modelMatrix = float4x4(1.0)
    var modelViewProjectionMatrix = float4x4(1.0)
    var normalMatrix = float3x3(1.0)
}
//------------------------------------------------------------------------------
struct MBJVertex
{
    var position = float4(0.0)
    var normal = float4(0.0)
    var texCoords = float2(0.0)
}
//------------------------------------------------------------------------------
typealias MBJIndexType = UInt16
//------------------------------------------------------------------------------
