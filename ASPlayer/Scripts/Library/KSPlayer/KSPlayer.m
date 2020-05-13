//
//  XPlayer.m
//  FFmpeg-project
//
//  Created by huizai on 2017/10/20.
//  Copyright © 2017年 huizai. All rights reserved.
//

#import "KSPlayer.h"
#import "KSOpenalPlayer.h"
#import "KSFFmpegDecoder.h"
#import "KSOpenGLView.h"
#import "KSYUVGL.h"

@interface KSPlayer (){
    UIView          *playView;
    KSFFmpegDecoder   *decoder;
    BOOL              isExit;
    NSLock          * lock;
    KSOpenalPlayer    *audioPlayer;
    NSMutableArray  * vPktArr;
    NSMutableArray  * aPktArr;
    __block UIImage * image;
    KSOpenGLView      * openGLView;
}

@end

@implementation KSPlayer

+ (instancetype)sharedPlayer{
    static dispatch_once_t onceToken;
    static KSPlayer *plyer = nil;
    dispatch_once(&onceToken, ^{
        plyer = [[KSPlayer alloc] init];
    });
    return plyer;
}

-(instancetype)init {
    if (self = [super init]) {
        if (![self initPlayer]) {
            return nil;
        }
    }
    return self;
}

- (int)openUrl:(NSString *)url playView:(UIView*)view{
    int result = 0;
    playView = view;
    openGLView = [[KSOpenGLView alloc]initWithFrame:view.frame];
    if (!openGLView) {
        NSLog(@"init gl fail...");
        return NO;
    }
    [openGLView setVideoSize:playView.frame.size.width height:playView.frame.size.height];
    [playView addSubview:openGLView];
    //初始化openal
    audioPlayer = [[KSOpenalPlayer alloc]init];
    if (!audioPlayer) {
        NSLog(@"init openal fail...");
        return NO;
    }
    if (![decoder openUrl:[url UTF8String]]) {
        result = -1;
    }
    return result;
}

- (BOOL)initPlayer {
    decoder = [[KSFFmpegDecoder alloc]init];
    _isStop = YES;
    if (!decoder) {
        NSLog(@"init decoder fail...");
        return NO;
    }
    lock = [[NSLock alloc]init];
    vPktArr = [NSMutableArray array];
    return YES;
}

- (void)play {
    if (_isStop) {
        [audioPlayer initOpenAL];
    }
    isExit = NO;
    [self startPlayThread];
    [audioPlayer playSound];
    _isStop = NO;
}

- (void)stop {
    isExit = YES;
    [audioPlayer stopSound];
    [audioPlayer cleanUpOpenAL];
    audioPlayer = nil;
    [vPktArr removeAllObjects];
    [decoder close];
    [openGLView clearFrame];
    [openGLView removeFromSuperview];
    openGLView = nil;
    _isStop = YES;
}

- (void)pause{
    _isStop = NO;
    isExit = YES;
    [audioPlayer stopSound];
}

//启动gcd多线程，读取解码播放
- (void)startPlayThread{
    dispatch_queue_t readQueue = dispatch_queue_create("readAudioQueeu", DISPATCH_QUEUE_CONCURRENT);
    dispatch_async(readQueue, ^{
        AVPacket *pkt = NULL;
        while (!isExit) {
            pkt = av_packet_alloc();
            [lock lock];
            [decoder readPacket:pkt];
            [lock unlock];
            
            if (pkt == NULL) {
                [NSThread sleepForTimeInterval:0.01];
                continue;
            }
            if (pkt->size <= 0) {
                [NSThread sleepForTimeInterval:0.01];
                continue;
            }
            if (pkt->stream_index == decoder.audioStreamIndex) {
                
                [lock lock];
                [decoder decodePacket:pkt];
                [lock unlock];
                av_packet_unref(pkt);
                
                char* tempData = (char*)malloc(10000);
                [lock lock];
                int length =  [decoder toPCM:tempData];
                [lock unlock];
                //用音频播放器播放
                [audioPlayer openAudioFromQueue:tempData andWithDataSize:length andWithSampleRate:decoder.sampleRate andWithAbit:decoder.sampleSize andWithAchannel:decoder.channel];
                free(tempData);
                //这里设置openal内部缓存数据的大小  太大了视频延迟大  太小了视频会卡顿 根据实际情况调整
                NSLog(@"++++++++++++++%d",audioPlayer.m_numqueued);
                if (audioPlayer.m_numqueued > 10 && audioPlayer.m_numqueued < 35) {
                    [NSThread sleepForTimeInterval:0.01];
                }else if (audioPlayer.m_numqueued > 35){
                    [NSThread sleepForTimeInterval:0.025];
                }
                continue;
            }else if (pkt->stream_index == decoder.videoStreamIndex){
                [lock lock];
                NSData * pktData = [NSData dataWithBytes:pkt length:sizeof(AVPacket)];
                [vPktArr insertObject:pktData atIndex:0];
                [lock unlock];
                continue;
                // av_packet_unref(pkt);
            }else{
                av_packet_unref(pkt);
                continue;
            }
        }
    });
    
    dispatch_queue_t videoPlayQueue = dispatch_queue_create("videoPlayQueeu", DISPATCH_QUEUE_CONCURRENT);
    dispatch_async(videoPlayQueue, ^{
        KSH264YUVFrame yuvFrame;
        while (!isExit) {
            NSLog(@"=========vPktArr.count:%lu",(unsigned long)vPktArr.count);
            if (vPktArr.count == 0) {
                [NSThread sleepForTimeInterval:0.01];
                NSLog(@"0000000000000000000000");
                continue;
            }
            //这里同步音视频播放速度
            NSLog(@"========vfps:%d,afps:%d",decoder.vFps,decoder.aFps);
            if ((decoder.vFps > decoder.aFps - 900 - _syncRate*1000)&& decoder.aFps>500) {
                NSLog(@"aaaaaaaaaaaaaaaaaaa");
                [NSThread sleepForTimeInterval:0.01];
                continue;
            }
            [lock lock];
            NSData * newData = [vPktArr lastObject];
            AVPacket* newPkt = (AVPacket*)[newData bytes];
            [vPktArr removeLastObject];
            [lock unlock];
            if (!newPkt) {
                continue;
            }
            [lock lock];
            [decoder decodePacket:newPkt];
            [lock unlock];
            av_packet_unref(newPkt);
            /*
             下面这段屏蔽代码是yuv转rgb
             rgb转image的
             如果不用opengl直接绘图yuv可以用下面的功能
             */
//            int width = 320;
//            int height = 250;
//            char* tempData = (char*)malloc(width*height*4 + 1);
//            [lock lock];
//            [decoder ToRGB:tempData andWithOutHeight:height andWithOutWidth:width];
//            image = [decoder ToImage:tempData andWithOutHeight:height andWithOutWidth:width];
//            free(tempData);
//            [lock unlock];
//            UIColor *color =  [UIColor colorWithPatternImage:image];
            [lock lock];
            memset(&yuvFrame, 0, sizeof(KSH264YUVFrame));
            yuvFrame = [decoder yuvToGlData:yuvFrame];
            if (yuvFrame.width == 0) {
                [lock unlock];
                continue;
            }
            [lock unlock];
            dispatch_async(dispatch_get_main_queue(), ^{
                // [self.imageView setImage:image];
                // playView.backgroundColor = color;
                [openGLView displayYUV420pData:(KSH264YUVFrame*)&yuvFrame];
                free(yuvFrame.luma.dataBuffer);
                free(yuvFrame.chromaB.dataBuffer);
                free(yuvFrame.chromaR.dataBuffer);
            });
        }
    });
}

- (BOOL)isDecoderExit{
    if (decoder) {
        return YES;
    }
    return NO;
}

- (void)setSyncRate:(float)syncRate{
    _syncRate = syncRate;
}

- (void)setPlayRate:(float)playRate{
    audioPlayer.playRate = playRate;
}

- (void)dealloc {
    if (playView) {
        playView = nil;
    }
    if (decoder) {
        decoder = nil;
    }
    if (audioPlayer) {
        [audioPlayer cleanUpOpenAL];
        audioPlayer = nil;
    }
    if (openGLView) {
        [openGLView clearFrame];
        openGLView = nil;
    }
    if (lock) {
        lock = nil;
    }
}

@end
