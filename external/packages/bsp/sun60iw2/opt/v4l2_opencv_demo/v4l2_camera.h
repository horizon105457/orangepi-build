/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * V4L2Camera - 简洁的V4L2摄像头采集类
 * 支持YUV420M格式，提供简单的初始化、启动、停止和获取帧接口
 */

#ifndef V4L2_CAMERA_H
#define V4L2_CAMERA_H

#include <string>
#include <linux/videodev2.h>
#include <opencv2/opencv.hpp>

class V4L2Camera {
public:
    V4L2Camera(const std::string& device, int width, int height);
    ~V4L2Camera();

    bool init();
    bool start();
    bool stop();
    bool getFrame(cv::Mat& frame);

private:
    struct Buffer {
        void* start[3];      // Y, U, V 三个平面
        size_t length[3];    // 每个平面的长度
    };

    bool initDevice();
    bool setFormat();
    bool requestBuffers();
    bool queueAllBuffers();
    bool releaseBuffers();
    void yuv420mToBgr(unsigned char* y_plane, unsigned char* u_plane, 
                     unsigned char* v_plane, cv::Mat& bgr_frame);

    static const int BUFFER_COUNT = 4;
    
    std::string device_;
    int width_;
    int height_;
    int fd_;
    bool streaming_;
    bool initialized_;
    
    Buffer buffers_[BUFFER_COUNT];
    unsigned int nplanes_;
};

#endif // V4L2_CAMERA_H
