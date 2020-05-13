//
//  FFmpegDecoder.h
//  FFmpeg-project
//
//  Created by huizai on 2017/9/14.
//  Copyright © 2017年 huizai. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "avcodec.h"
#import "swscale.h"
#import "avformat.h"
#import "swresample.h"
#import "samplefmt.h"
#import "KSYUVGL.h"

@interface KSFFmpegDecoder : NSObject
//总时长
@property (nonatomic,assign)int  totalMs;
//音频播放时间
@property (nonatomic,assign)int  aFps;
//视频播放时间
@property (nonatomic,assign)int  vFps;
//视频流索引
@property (nonatomic,assign)int  videoStreamIndex;
//音频流索引
@property (nonatomic,assign)int  audioStreamIndex;
@property (nonatomic,assign)int  sampleRate;
@property (nonatomic,assign)int  sampleSize;
@property (nonatomic,assign)int  channel;
//音频贞数据的长度
@property (nonatomic,assign)int  pcmDataLength;


#pragma mark - 接口
- (BOOL)openUrl:(const char*)path;
- (void)readPacket:(AVPacket*)pkt;
- (void)decodePacket:(AVPacket*)pkt;
- (KSH264YUVFrame)yuvToGlData:(KSH264YUVFrame)yuvFrame;
- (BOOL)toRGB:(char*)outBuf outHeight:(int)outHeight outWidth:(int)outWidth;
- (UIImage*)toImage:(char*)dataBuf outHeight:(int)outHeight outWidth:(int)outWidth;
//音频重采样
- (int)toPCM:(char*)dataBuf;
//获取错误信息
- (NSString*)getError;
- (void)close;

@end
