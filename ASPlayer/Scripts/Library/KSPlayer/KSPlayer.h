//
//  XPlayer.h
//  FFmpeg-project
//
//  Created by huizai on 2017/10/20.
//  Copyright © 2017年 huizai. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface KSPlayer : NSObject

//播放速率
@property (nonatomic ,assign)float  playRate;
//音视频同步参数
@property (nonatomic ,assign)float  syncRate;
@property (nonatomic ,assign)BOOL   isStop;

+ (instancetype)sharedPlayer;
- (int)openUrl:(NSString *)url playView:(UIView*)view;
- (void)play;
- (void)stop;
- (void)pause;

@end
