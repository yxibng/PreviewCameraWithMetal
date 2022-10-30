//
//  Shaders.metal
//  PreviewWithMetal
//
//  Created by xiaobing yao on 2022/10/28.
//

#include <metal_stdlib>
#include <simd/simd.h>
using namespace metal;

#include "ShaderTypes.h"

struct Vertex {
  float4 position [[position]];
  float2 textCoordiante;
};

vertex Vertex vertex_shader(constant PWMVertex *vertexArray [[buffer(0)]],
                            constant PWMMatrix &mvpMatrix [[buffer(1)]],
                            uint vid [[vertex_id]]) {
  Vertex out;
  out.position = mvpMatrix.mvp * vertexArray[vid].position;
  out.textCoordiante = vertexArray[vid].textureCoordinate;
  return out;
}

fragment float4 fragment_shader_nv12(Vertex in [[stage_in]],
                                     texture2d<half> textureY [[texture(0)]],
                                     texture2d<half> textureUV [[texture(1)]]) {
  constexpr sampler linearSampler(mip_filter::nearest, mag_filter::linear,
                                  min_filter::linear);
  float y = textureY.sample(linearSampler, in.textCoordiante).r;
  float u = textureUV.sample(linearSampler, in.textCoordiante).r - 0.5;
  float v = textureUV.sample(linearSampler, in.textCoordiante).g - 0.5;
  float r = y + 1.402 * v;
  float g = y - 0.344 * u - 0.714 * v;
  float b = y + 1.772 * u;
  return float4(r, g, b, 1.0);
}
