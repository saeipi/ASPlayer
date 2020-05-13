//
//  FFmpegDecoder.m
//  FFmpeg-project
//
//  Created by huizai on 2017/9/14.
//  Copyright © 2017年 huizai. All rights reserved.
//

#import "KSFFmpegDecoder.h"

//定义音频重采样后的参数
#define SAMPLE_SIZE 16
#define SAMPLE_RATE 44100
#define CHANNEL     2

@implementation KSFFmpegDecoder{

    char errorBuf[1024];
    NSLock   *lock;
    AVFormatContext   * pFormatCtx;
    AVCodecContext    * pVideoCodecCtx;
    AVCodecContext    * pAudioCodecCtx;
    AVFrame           * pYuv;        
    AVFrame           * pPcm;
    AVCodec           * pVideoCodec; //视频解码器
    AVCodec           * pAudioCodec; //音频解码器
    struct SwsContext * pSwsCtx;
    SwrContext        * pSwrCtx;
    char              * rgb;
    UIImage           * tempImage;
}

-(instancetype)init {
    if (self = [super init]) {
        [self initParam];
    }
    return self;
}

- (void)initParam {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        av_register_all();
        avformat_network_init();
    });
    _pcmDataLength = 0;
    _sampleRate = SAMPLE_RATE;
    _sampleSize = SAMPLE_SIZE;
    _channel = CHANNEL;
    lock = [[NSLock alloc]init];
}

- (double)r2d:(AVRational)r {
    return r.num == 0 || r.den == 0 ? 0.:(double)r.num/(double)r.den;
}

- (BOOL)openUrl:(const char*)path{
    [self close];
    [lock lock];
    int result = avformat_open_input(&pFormatCtx, path, 0, 0);
    if (result != 0) {
        [lock unlock];
        av_strerror(result, errorBuf, sizeof(errorBuf));
        return false;
    }
    _totalMs = (int)(pFormatCtx->duration/AV_TIME_BASE)*1000;
    avformat_find_stream_info(pFormatCtx, NULL);
    //分别找到音频视频解码器并打开解码器
    for (int i = 0; i < pFormatCtx->nb_streams; i++) {
        AVStream *stream = pFormatCtx->streams[i];
        AVCodec * codec = avcodec_find_decoder(stream->codecpar->codec_id);
        AVCodecContext * codecCtx = avcodec_alloc_context3(codec);
        avcodec_parameters_to_context(codecCtx, stream->codecpar);
        
        if (codecCtx->codec_type == AVMEDIA_TYPE_VIDEO) {
            printf("video\n");
            _videoStreamIndex = i;
            pVideoCodec  = codec;
            pVideoCodecCtx = codecCtx;
            int err = avcodec_open2(pVideoCodecCtx, pVideoCodec, NULL);
            if (err != 0) {
                [lock unlock];
                char buf[1024] = {0};
                av_strerror(err, buf, sizeof(buf));
                printf("open videoCodec error:%s", buf);
                return false;
            }
        }
        if (codecCtx->codec_type == AVMEDIA_TYPE_AUDIO) {
            printf("audio\n");
            _audioStreamIndex = i;
            pAudioCodec  = codec;
            pAudioCodecCtx = codecCtx;
            int err = avcodec_open2(pAudioCodecCtx, pAudioCodec, NULL);
            if (err != 0) {
                [lock unlock];
                char buf[1024] = {0};
                av_strerror(err, buf, sizeof(buf));
                printf("open audionCodec error:%s", buf);
                return false;
            }
            if (codecCtx->sample_rate != SAMPLE_RATE) {
                _sampleRate = codecCtx->sample_rate;
            }
        }
    }
    printf("open acodec success! sampleRate:%d  channel:%d  sampleSize:%d fmt:%d\n",_sampleRate,_channel,_sampleSize,pAudioCodecCtx->sample_fmt);
    [lock unlock];
    return true;
}

- (void)readPacket:(AVPacket*)pkt{
    //这里先不加线程锁，在启动多线程的地方统一加锁
    // AVPacket * pkt = malloc(sizeof(AVPacket));
    if (!pFormatCtx) {
        av_packet_unref(pkt);
        return;
    }
    int err = av_read_frame(pFormatCtx, pkt);
    if (err != 0) {
        av_strerror(err, errorBuf, sizeof(errorBuf));
        printf("av_read_frame error:%s",errorBuf);
        av_packet_unref(pkt);
        return ;
    }
}

- (void)decodePacket:(AVPacket*)pkt{
    
    if (!pFormatCtx) {
        return ;
    }
    //分配AVFream 空间
    if (pYuv == NULL) {
        pYuv = av_frame_alloc();
    }
    if (pPcm == NULL) {
        pPcm = av_frame_alloc();
    }
    AVCodecContext * pCodecCtx;
    AVFrame * tempFrame;
    if (pkt->stream_index == _videoStreamIndex) {
        pCodecCtx = pVideoCodecCtx;
        tempFrame = pYuv;
    }else if (pkt->stream_index == _audioStreamIndex){
        pCodecCtx = pAudioCodecCtx;
        tempFrame = pPcm;
    }else{
        return;
    }
    if (!pCodecCtx) {
        return;
    }
    int re = avcodec_send_packet(pCodecCtx, pkt);
    if (re != 0) {
        return;
    }
    re = avcodec_receive_frame(pCodecCtx, tempFrame);
    //解码后再获取pts  解码过程有缓存
    if (pkt->stream_index == _videoStreamIndex) {
        _vFps = (pYuv->pts *[self r2d:(pFormatCtx->streams[_videoStreamIndex]->time_base)])*1000;
    }else if (pkt->stream_index == _audioStreamIndex){
        _aFps = (pPcm->pts * [self r2d:(pFormatCtx->streams[_audioStreamIndex]->time_base)])*1000;
    }
    printf("[D]");

    return;
}

- (KSH264YUVFrame)yuvToGlData:(KSH264YUVFrame)yuvFrame{

    if (!pFormatCtx || !pYuv || pYuv->linesize[0] <= 0) {
        return yuvFrame;
    }
    //把数据重新封装成opengl需要的格式
    unsigned int lumaLength= (pYuv->height)*(MIN(pYuv->linesize[0], pYuv->width));
    unsigned int chromBLength=((pYuv->height)/2)*(MIN(pYuv->linesize[1], (pYuv->width)/2));
    unsigned int chromRLength=((pYuv->height)/2)*(MIN(pYuv->linesize[2], (pYuv->width)/2));

    yuvFrame.luma.dataBuffer = malloc(lumaLength);
    yuvFrame.chromaB.dataBuffer = malloc(chromBLength);
    yuvFrame.chromaR.dataBuffer = malloc(chromRLength);
    
    yuvFrame.width=pYuv->width;
    yuvFrame.height=pYuv->height;
    
    if (pYuv->height <= 0) {
        free(yuvFrame.luma.dataBuffer);
        free(yuvFrame.chromaB.dataBuffer);
        free(yuvFrame.chromaR.dataBuffer);
        return yuvFrame;
    }
    //复制
    copyDecodedFrame(pYuv->data[0],yuvFrame.luma.dataBuffer,pYuv->linesize[0],
                     pYuv->width,pYuv->height);
    copyDecodedFrame(pYuv->data[1], yuvFrame.chromaB.dataBuffer,pYuv->linesize[1],
                     pYuv->width / 2,pYuv->height / 2);
    copyDecodedFrame(pYuv->data[2], yuvFrame.chromaR.dataBuffer,pYuv->linesize[2],
                     pYuv->width / 2,pYuv->height / 2);
    return yuvFrame;
    
}

void copyDecodedFrame(unsigned char *src, unsigned char *dist,int linesize, int width, int height)
{
    width = MIN(linesize, width);
    if (sizeof(dist) == 0) {
        return;
    }
    for (NSUInteger i = 0; i < height; ++i) {
        memcpy(dist, src, width);
        dist += width;
        src += linesize;
    }
}

- (int)toPCM:(char*)dataBuf{

    if (!pFormatCtx || !pPcm || !dataBuf) {
        return 0;
    }
    printf("sample_rate:%d,channels:%d,sample_fmt:%d,channel_layout:%llu,nb_samples:%d\n",pAudioCodecCtx->sample_rate,pAudioCodecCtx->channels,pAudioCodecCtx->sample_fmt,pAudioCodecCtx->channel_layout,pPcm->nb_samples);
    //音频重采样
    if (pSwrCtx == NULL) {
        pSwrCtx = swr_alloc();
        swr_alloc_set_opts(pSwrCtx,
                           AV_CH_LAYOUT_STEREO,//2声道立体声
                           AV_SAMPLE_FMT_S16,  //采样大小 16位
                           _sampleRate,        //采样率
                           pAudioCodecCtx->channel_layout,
                           pAudioCodecCtx->sample_fmt,// 样本类型
                           pAudioCodecCtx->sample_rate,
                           0, 0);
        swr_init(pSwrCtx);
    }
    uint8_t * data[1];
    [lock lock];
    data[0] = (uint8_t*)dataBuf;
    int len = swr_convert(pSwrCtx, data, 10000, (const uint8_t**)pPcm->data, pPcm->nb_samples);
    if (len < 0) {
        [lock unlock];
        return 0;
    }
    
    int outSize = av_samples_get_buffer_size(NULL,
                                             CHANNEL,
                                             len,
                                             AV_SAMPLE_FMT_S16,0);
    _pcmDataLength = outSize;
    NSLog(@"nb_smples:%d,des_smples:%d,outSize:%d",pPcm->nb_samples,len,outSize);
    [lock unlock];
    return outSize;
}

- (BOOL)toRGB:(char*)outBuf outHeight:(int)outHeight outWidth:(int)outWidth{

    if (!pFormatCtx || !pYuv || pYuv->linesize[0] <= 0) {
        return false;
    }
    //视频yuv转rgb 并转换视频frame的大小
    pSwsCtx = sws_getCachedContext(pSwsCtx, pVideoCodecCtx->width,
                                   pVideoCodecCtx->height,
                                   pVideoCodecCtx->pix_fmt,
                                   outWidth, outHeight,
                                   AV_PIX_FMT_RGB24,
                                   SWS_BICUBIC, NULL, NULL, NULL);
    if (pSwsCtx) {
        // printf("sws_getCachedContext success!\n");
    }else{
        printf("sws_getCachedContext fail!\n");
        return false;
    }
    
    uint8_t * data[AV_NUM_DATA_POINTERS]={0};
    data[0] = (uint8_t*)outBuf;
    int linesize[AV_NUM_DATA_POINTERS] = {0};
    linesize[0] = outWidth * 4;
    int h = sws_scale(pSwsCtx, (const uint8_t* const*)pYuv->data, pYuv->linesize, 0, pVideoCodecCtx->height,data,linesize);
    if (h > 0) {
        printf("H:%d",h);
    }
    return true;
}

- (UIImage*)toImage:(char*)dataBuf outHeight:(int)outHeight outWidth:(int)outWidth{

    //rgb 数据转换成为image  
    int linesize[AV_NUM_DATA_POINTERS] = {0};
    linesize[0] = outWidth * 4;
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    void * colorData = NULL;
    memcpy(&colorData, &dataBuf, sizeof(dataBuf));
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, colorData, sizeof(colorData), NULL);
    CGImageRef cgImage = CGImageCreate(outWidth,
                                       outHeight,
                                       8,
                                       24,
                                       linesize[0],
                                       colorSpace,
                                       bitmapInfo,
                                       provider,
                                       NULL,
                                       NO,
                                       kCGRenderingIntentDefault);
    UIImage * image = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);
    tempImage = image;
    return image;
}


- (void)close{

    [lock lock];
    if (pFormatCtx) {
        avformat_close_input(&pFormatCtx);
    }
    if (pSwrCtx) {
        swr_free(&pSwrCtx);
    }
    if (pSwsCtx) {
        sws_freeContext(pSwsCtx);
    }
    avcodec_close(pVideoCodecCtx);
    avcodec_close(pAudioCodecCtx);
    if (pYuv) {
        av_frame_free(&pYuv);
    }
    if (pPcm) {
        av_frame_free(&pPcm);
    }
    [lock unlock];
}


- (NSString*)getError{
    [lock lock];
    NSString * err = [NSString stringWithUTF8String:errorBuf];
    [lock unlock];
    return err;
}

@end
