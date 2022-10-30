//
//  ShaderTypes.h
//  PreviewWithMetal
//
//  Created by xiaobing yao on 2022/10/28.
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

typedef struct {
  vector_float4 position;
  vector_float2 textureCoordinate;
} PWMVertex;

typedef struct {
  matrix_float4x4 mvp;
} PWMMatrix;

typedef uint16_t PWMIndex;

#endif /* ShaderTypes_h */
