//
//  ViewController.m
//  PreviewWithMetal
//
//  Created by xiaobing yao on 2022/10/27.
//

#import "VideoCapturer.h"
#import "ViewController.h"
#import <MetalKit/MetalKit.h>

#import "MBEMathUtilities.h"
#import "ShaderTypes.h"

// 弧度转角度
#define Radians_To_Degrees(radians) ((radians) * (180.0 / M_PI))
// 角度转弧度
#define Degrees_To_Radians(angle) ((angle) / 180.0 * M_PI)

typedef NS_ENUM(NSUInteger, PWMContentsGravity) {
  PWMContentsGravityResize,
  PWMContentsGravityResizeAspect,
  PWMContentsGravityResizeAspectFill,
};

typedef NS_ENUM(NSUInteger, PWMRotation) {
  PWMRotation_0 = 0,
  PWMRotation_90 = 90,
  PWMRotation_180 = 180,
  PWMRotation_270 = 270
};

@interface ViewController () <VideoCaptuerDelegate, MTKViewDelegate>

@property(nonatomic, strong) VideoCapturer *videoCapturer;
@property(weak) IBOutlet MTKView *metalView;

@property(strong) id<MTLDevice> device;
@property(strong) id<MTLCommandQueue> commandQueue;
@property(strong) id<MTLRenderPipelineState> renderPipelineState;

@property(strong) id<MTLBuffer> vertexBuffer;
@property(strong) id<MTLBuffer> indexBuffer;
@property(strong) id<MTLBuffer> matrixBuffer;
@property(nonatomic) CVMetalTextureCacheRef textureCache;
@property(nonatomic) MTLViewport viewport;

@property(nonatomic) PWMContentsGravity contentGravity;
@property(nonatomic) PWMRotation rotation;

@property(nonatomic) PWMMatrix matrix;

@end

@implementation ViewController

- (void)dealloc {
  if (self.textureCache) {
    CVMetalTextureCacheFlush(self.textureCache, 0);
    CFRelease(self.textureCache);
    self.textureCache = NULL;
  }
}

- (void)viewDidLoad {
  [super viewDidLoad];
  VideoConifg *config = [[VideoConifg alloc] init];
  config.videoSize = CGSizeMake(1280, 720);
  _videoCapturer = [[VideoCapturer alloc] initWithConfig:config delegate:self];
  self.matrix = (PWMMatrix){matrix_float4x4_identity()};
  [self setup];
}

- (void)setup {
  _device = MTLCreateSystemDefaultDevice();
  _metalView.wantsLayer = YES;
  _metalView.device = _device;

  _contentGravity = PWMContentsGravityResize;
  _rotation = PWMRotation_0;

  [self makePipeline];
  [self makeBuffers];

  self.commandQueue = [self.device newCommandQueue];

  CVReturn ret =
      CVMetalTextureCacheCreate(NULL, NULL, self.device, NULL, &_textureCache);
  if (ret) {
    NSLog(@"CVMetalTextureCacheCreate failed");
  }
}

- (void)makePipeline {
  id<MTLLibrary> library = [self.device newDefaultLibrary];
  MTLRenderPipelineDescriptor *pipelineDescriptor =
      [[MTLRenderPipelineDescriptor alloc] init];
  pipelineDescriptor.vertexFunction =
      [library newFunctionWithName:@"vertex_shader"];
  pipelineDescriptor.fragmentFunction =
      [library newFunctionWithName:@"fragment_shader_nv12"];

  pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

  NSError *error = nil;
  self.renderPipelineState =
      [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor
                                                  error:&error];
  if (!self.renderPipelineState) {
    NSLog(@"Error occurred when creating render pipeline state: %@", error);
  }
}

- (void)makeBuffers {

  static const PWMVertex verteices[] = {
      {.position = {-1, -1, 1, 1}, .textureCoordinate = {0, 1}},
      {.position = {-1, 1, 1, 1}, .textureCoordinate = {0, 0}},
      {.position = {1, 1, 1, 1}, .textureCoordinate = {1, 0}},
      {.position = {1, -1, 1, 1}, .textureCoordinate = {1, 1}}};

  static const PWMIndex indeices[] = {0, 1, 2, 0, 2, 3};

  _vertexBuffer =
      [self.device newBufferWithBytes:verteices
                               length:sizeof(verteices)
                              options:MTLResourceOptionCPUCacheModeDefault];
  [_vertexBuffer setLabel:@"Vertices"];

  _indexBuffer =
      [self.device newBufferWithBytes:indeices
                               length:sizeof(indeices)
                              options:MTLResourceOptionCPUCacheModeDefault];
  [_indexBuffer setLabel:@"Indeices"];

  _matrixBuffer =
      [self.device newBufferWithLength:sizeof(PWMMatrix)
                               options:MTLResourceOptionCPUCacheModeDefault];
  [_matrixBuffer setLabel:@"MVPMatrix"];

  PWMMatrix matrix = self.matrix;
  memcpy(_matrixBuffer.contents, &matrix, sizeof(matrix));
}

- (IBAction)startRunning:(id)sender {
  [_videoCapturer start];
}

- (IBAction)stopRunning:(id)sender {
  [_videoCapturer stop];
}

- (IBAction)rotateLeft:(id)sender {
  _rotation = (_rotation - 90 + 360) % 360;
  PWMMatrix matrix = self.matrix;
  matrix.mvp = matrix_float4x4_rotation((vector_float3){0, 0, 1},
                                        Degrees_To_Radians(_rotation));
  self.matrix = matrix;
  memcpy(_matrixBuffer.contents, &matrix, sizeof(matrix));
}
- (IBAction)rotateRight:(id)sender {
  _rotation = (_rotation + 90) % 360;
  PWMMatrix matrix = self.matrix;
  matrix.mvp = matrix_float4x4_rotation((vector_float3){0, 0, 1},
                                        Degrees_To_Radians(_rotation));
  self.matrix = matrix;
  memcpy(_matrixBuffer.contents, &matrix, sizeof(matrix));
}
- (IBAction)flipHorizontal:(id)sender {
  PWMMatrix matrix = self.matrix;
  matrix.mvp.columns[0][0] *= -1;
  self.matrix = matrix;
  memcpy(_matrixBuffer.contents, &matrix, sizeof(matrix));
}
- (IBAction)flipVertical:(id)sender {
  PWMMatrix matrix = self.matrix;
  matrix.mvp.columns[1][1] *= -1;
  self.matrix = matrix;
  memcpy(_matrixBuffer.contents, &matrix, sizeof(matrix));
}
- (IBAction)onContentGravityChange:(NSPopUpButton *)sender {
  self.contentGravity = sender.indexOfSelectedItem;
}

- (void)calculateViewportWithFrameWidth:(int)width height:(int)height {

  CGSize drawSize = [self.metalView currentDrawable].layer.drawableSize;
  float aspect = width / (float)height;
  switch (self.contentGravity) {
  case PWMContentsGravityResize: {
    MTLViewport viewport = {.originX = 0,
                            .originY = 0,
                            .width = drawSize.width,
                            .height = drawSize.height,
                            .znear = 0,
                            .zfar = 1};
    self.viewport = viewport;
  } break;
  case PWMContentsGravityResizeAspectFill: {
    if (drawSize.width / drawSize.height < aspect) {
      int viewportWidth = drawSize.height * aspect;
      int x = (drawSize.width - viewportWidth) / 2;
      MTLViewport viewport = {.originX = x,
                              .originY = 0,
                              .width = viewportWidth,
                              .height = drawSize.height,
                              .znear = 0,
                              .zfar = 1};
      self.viewport = viewport;
    } else {
      int viewportHeight = drawSize.width / aspect;
      int y = (drawSize.height - viewportHeight) / 2;
      MTLViewport viewport = {.originX = 0,
                              .originY = y,
                              .width = drawSize.width,
                              .height = viewportHeight,
                              .znear = 0,
                              .zfar = 1};
      self.viewport = viewport;
    }
  } break;
  case PWMContentsGravityResizeAspect: {
    if (drawSize.width / drawSize.height > aspect) {
      int viewportWidth = drawSize.height * aspect;
      int x = (drawSize.width - viewportWidth) / 2;
      MTLViewport viewport = {.originX = x,
                              .originY = 0,
                              .width = viewportWidth,
                              .height = drawSize.height,
                              .znear = 0,
                              .zfar = 1};
      self.viewport = viewport;
    } else {
      int viewportHeight = drawSize.width / aspect;
      int y = (drawSize.height - viewportHeight) / 2;
      MTLViewport viewport = {.originX = 0,
                              .originY = y,
                              .width = drawSize.width,
                              .height = viewportHeight,
                              .znear = 0,
                              .zfar = 1};
      self.viewport = viewport;
    }
  } break;
  }
}

- (void)videoCapturer:(VideoCapturer *)capturer
    didGotSampleBuffer:(CMSampleBufferRef)sampleBuffer {

  CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);

  CVPixelBufferLockBaseAddress(pixelBuffer, 0);

  int width = (int)CVPixelBufferGetWidth(pixelBuffer);
  int height = (int)CVPixelBufferGetHeight(pixelBuffer);

  CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

  if (_rotation == PWMRotation_90 || _rotation == PWMRotation_270) {
    [self calculateViewportWithFrameWidth:height height:width];
  } else {
    [self calculateViewportWithFrameWidth:width height:height];
  }

  CVMetalTextureRef textureY, textureUV;

  CVMetalTextureCacheCreateTextureFromImage(
      NULL, self.textureCache, pixelBuffer, NULL, MTLPixelFormatR8Unorm,
      CVPixelBufferGetWidthOfPlane(pixelBuffer, 0),
      CVPixelBufferGetHeightOfPlane(pixelBuffer, 0), 0, &textureY);

  CVMetalTextureCacheCreateTextureFromImage(
      NULL, self.textureCache, pixelBuffer, NULL, MTLPixelFormatRG8Unorm,
      CVPixelBufferGetWidthOfPlane(pixelBuffer, 1),
      CVPixelBufferGetHeightOfPlane(pixelBuffer, 1), 1, &textureUV);

  id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
  MTLRenderPassDescriptor *renderPassDescriptor =
      [[MTLRenderPassDescriptor alloc] init];
  renderPassDescriptor.colorAttachments[0].clearColor =
      MTLClearColorMake(0, 0, 0, 1);
  renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
  renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
  renderPassDescriptor.colorAttachments[0].texture =
      [self.metalView currentDrawable].texture;
  id<MTLRenderCommandEncoder> encoder =
      [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];

  [encoder setRenderPipelineState:self.renderPipelineState];
  [encoder setVertexBuffer:self.vertexBuffer offset:0 atIndex:0];
  [encoder setVertexBuffer:self.matrixBuffer offset:0 atIndex:1];
  [encoder setViewport:self.viewport];
  [encoder setFragmentTexture:CVMetalTextureGetTexture(textureY) atIndex:0];
  [encoder setFragmentTexture:CVMetalTextureGetTexture(textureUV) atIndex:1];
  [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                      indexCount:6
                       indexType:MTLIndexTypeUInt16
                     indexBuffer:self.indexBuffer
               indexBufferOffset:0];
  [encoder setViewport:self.viewport];
  [encoder endEncoding];
  [commandBuffer presentDrawable:[self.metalView currentDrawable]];
  [commandBuffer commit];

  CVBufferRelease(textureY);
  CVBufferRelease(textureUV);
}

- (void)setRepresentedObject:(id)representedObject {
  [super setRepresentedObject:representedObject];

  // Update the view, if already loaded.
}

- (void)drawInMTKView:(nonnull MTKView *)view {
}

- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size {
}

@end
