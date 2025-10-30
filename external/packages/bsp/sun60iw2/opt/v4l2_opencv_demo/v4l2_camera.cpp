/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * V4L2Camera 实现文件
 */

#include "v4l2_camera.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/mman.h>

#define V4L2_MODE_VIDEO			0x0002

#define CLEAR(x) (memset(&(x), 0, sizeof(x)))

V4L2Camera::V4L2Camera(const std::string& device, int width, int height)
    : device_(device), width_(width), height_(height), fd_(-1),
      streaming_(false), initialized_(false), nplanes_(3) {
}

V4L2Camera::~V4L2Camera() {
    stop();
    if (initialized_) {
        releaseBuffers();
        if (fd_ >= 0) {
            close(fd_);
        }
    }
}

bool V4L2Camera::init() {
    if (initialized_) {
        return true;
    }

    if (!initDevice() || !setFormat() || !requestBuffers() || !queueAllBuffers()) {
        return false;
    }

    initialized_ = true;
    return true;
}

bool V4L2Camera::start() {
    if (!initialized_) {
        return false;
    }

    if (streaming_) {
        return true;
    }

    enum v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
    if (ioctl(fd_, VIDIOC_STREAMON, &type) == -1) {
        return false;
    }

    streaming_ = true;
    return true;
}

bool V4L2Camera::stop() {
    if (!streaming_) {
        return true;
    }

    enum v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
    if (ioctl(fd_, VIDIOC_STREAMOFF, &type) == -1) {
        return false;
    }

    streaming_ = false;
    return true;
}

bool V4L2Camera::getFrame(cv::Mat& frame) {
    if (!streaming_) {
        return false;
    }

    // 等待帧数据
    fd_set fds;
    struct timeval tv = {1, 0};
    
    FD_ZERO(&fds);
    FD_SET(fd_, &fds);
    
    int ret = select(fd_ + 1, &fds, NULL, NULL, &tv);
    if (ret <= 0) {
        return false;
    }

    // 出队缓冲区
    struct v4l2_buffer buf;
    struct v4l2_plane planes[3];
    
    CLEAR(buf);
    buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
    buf.memory = V4L2_MEMORY_MMAP;
    buf.length = nplanes_;
    buf.m.planes = planes;

    if (ioctl(fd_, VIDIOC_DQBUF, &buf) == -1) {
        return false;
    }

    // 转换为BGR格式
    if (nplanes_ >= 3) {
        yuv420mToBgr((unsigned char*)buffers_[buf.index].start[0],
                     (unsigned char*)buffers_[buf.index].start[1],
                     (unsigned char*)buffers_[buf.index].start[2],
                     frame);
    }

    // 重新入队缓冲区
    if (ioctl(fd_, VIDIOC_QBUF, &buf) == -1) {
        return false;
    }

    return true;
}

bool V4L2Camera::initDevice() {
    fd_ = open(device_.c_str(), O_RDWR | O_NONBLOCK, 0);
    if (fd_ < 0) {
        return false;
    }

    // 设置输入源
    struct v4l2_input inp;
    CLEAR(inp);
    inp.index = 0;
    ioctl(fd_, VIDIOC_S_INPUT, &inp); // 忽略错误，不是所有设备都需要

    // 设置流参数
    struct v4l2_streamparm parms;
    CLEAR(parms);
    parms.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
    parms.parm.capture.timeperframe.numerator = 1;
    parms.parm.capture.timeperframe.denominator = 30;
    parms.parm.capture.capturemode = V4L2_MODE_VIDEO;
    ioctl(fd_, VIDIOC_S_PARM, &parms); // 忽略错误

    return true;
}

bool V4L2Camera::setFormat() {
    struct v4l2_format fmt;
    CLEAR(fmt);
    
    fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
    fmt.fmt.pix_mp.width = width_;
    fmt.fmt.pix_mp.height = height_;
    fmt.fmt.pix_mp.pixelformat = V4L2_PIX_FMT_YUV420M;
    fmt.fmt.pix_mp.field = V4L2_FIELD_NONE;

    if (ioctl(fd_, VIDIOC_S_FMT, &fmt) == -1) {
        return false;
    }

    // 获取实际设置的格式
    if (ioctl(fd_, VIDIOC_G_FMT, &fmt) == -1) {
        return false;
    }

    nplanes_ = fmt.fmt.pix_mp.num_planes;
    width_ = fmt.fmt.pix_mp.width;
    height_ = fmt.fmt.pix_mp.height;

    return true;
}

bool V4L2Camera::requestBuffers() {
    struct v4l2_requestbuffers req;
    CLEAR(req);
    
    req.count = BUFFER_COUNT;
    req.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
    req.memory = V4L2_MEMORY_MMAP;
    
    if (ioctl(fd_, VIDIOC_REQBUFS, &req) == -1) {
        return false;
    }

    // 查询并映射每个缓冲区
    for (unsigned int i = 0; i < BUFFER_COUNT; i++) {
        struct v4l2_buffer buf;
        struct v4l2_plane planes[3];
        
        CLEAR(buf);
        buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
        buf.memory = V4L2_MEMORY_MMAP;
        buf.index = i;
        buf.length = nplanes_;
        buf.m.planes = planes;

        if (ioctl(fd_, VIDIOC_QUERYBUF, &buf) == -1) {
            return false;
        }

        // 映射每个平面
        for (unsigned int j = 0; j < nplanes_; j++) {
            buffers_[i].length[j] = planes[j].length;
            buffers_[i].start[j] = mmap(NULL, planes[j].length,
                                      PROT_READ | PROT_WRITE,
                                      MAP_SHARED, fd_, 
                                      planes[j].m.mem_offset);
            
            if (buffers_[i].start[j] == MAP_FAILED) {
                return false;
            }
        }
    }

    return true;
}

bool V4L2Camera::queueAllBuffers() {
    for (unsigned int i = 0; i < BUFFER_COUNT; i++) {
        struct v4l2_buffer buf;
        struct v4l2_plane planes[3];
        
        CLEAR(buf);
        buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
        buf.memory = V4L2_MEMORY_MMAP;
        buf.index = i;
        buf.length = nplanes_;
        buf.m.planes = planes;

        if (ioctl(fd_, VIDIOC_QBUF, &buf) == -1) {
            return false;
        }
    }
    
    return true;
}

bool V4L2Camera::releaseBuffers() {
    for (unsigned int i = 0; i < BUFFER_COUNT; i++) {
        for (unsigned int j = 0; j < nplanes_; j++) {
            if (buffers_[i].start[j] != MAP_FAILED) {
                munmap(buffers_[i].start[j], buffers_[i].length[j]);
            }
        }
    }
    return true;
}

void V4L2Camera::yuv420mToBgr(unsigned char* y_plane, unsigned char* u_plane, 
                             unsigned char* v_plane, cv::Mat& bgr_frame) {
    cv::Mat yuv_frame(height_ * 3 / 2, width_, CV_8UC1);
    
    // 复制Y平面
    memcpy(yuv_frame.data, y_plane, width_ * height_);
    
    // 复制UV平面
    unsigned char* uv_dst = yuv_frame.data + width_ * height_;
    int uv_size = width_ * height_ / 4;
    memcpy(uv_dst, u_plane, uv_size);
    memcpy(uv_dst + uv_size, v_plane, uv_size);
    
    cv::cvtColor(yuv_frame, bgr_frame, cv::COLOR_YUV2BGR_I420);
}
