//
//  KSYUVGL.h
//  FFmpeg-project
//
//  Created by saeipi on 2020/5/12.
//  Copyright © 2020 huizai. All rights reserved.
//

#ifndef KSYUVGL_h
#define KSYUVGL_h

typedef struct H264FrameDef
{
    unsigned int    length;
    unsigned char*  dataBuffer;
    
}KSH264Frame;

typedef struct  H264YUVDef
{
    unsigned int    width;
    unsigned int    height;
    KSH264Frame       luma;
    KSH264Frame       chromaB;
    KSH264Frame       chromaR;
    
}KSH264YUVFrame;

#endif /* KSYUVGL_h */
