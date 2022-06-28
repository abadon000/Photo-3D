//
//  Shader.metal
//  PhotoTo3D
//
//  Created by lcy on 2022/6/17.
//  Copyright © 2022 admin. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn
{
    packed_float4  position;
    packed_float2  uv;
};

struct VertexOut
{
    float4  position [[position]];
    float2  uv;
    float pointSize [[ point_size ]];
};

struct Uniforms
{
    packed_float2 pointTexcoordScale;
    float pointSizeInPixel;
};

constexpr sampler s(coord::normalized, address::repeat, filter::linear);

vertex VertexOut vertex_func(uint vid [[vertex_id]],
                             texture2d<float> diffuse [[texture(0)]],
                             const device VertexIn* vertexIn [[buffer(0)]],
                             const device float4x4& model [[buffer(1)]],
                             const device float4x4& view [[buffer(2)]],
                             const device float4x4& perspective [[buffer(3)]],
                             const device Uniforms& uniforms [[buffer(4)]])
{
    VertexOut outVertex;
    VertexIn inVertex = vertexIn[vid];
    float4 color =  diffuse.sample(s, inVertex.uv);
    inVertex.position.z = 0.3 * (0.299 * color.r + 0.587 * color.g + 0.114 * color.b);
    outVertex.uv = inVertex.uv;
    outVertex.position = perspective * view * model * float4(inVertex.position);
    outVertex.pointSize = uniforms.pointSizeInPixel;
                                                                 
    return outVertex;
};

fragment float4 fragment_func(VertexOut infrag [[stage_in]], texture2d<float> diffuse [[texture(0)]]) {
    
    float4 imageColor = diffuse.sample(s, infrag.uv);
    return imageColor;
};


