#include "v4l2_camera.h"
#include <opencv2/opencv.hpp>
#include <chrono>
#include <iostream>

int main(int argc, char* argv[])
{
	const char* device = "/dev/video8";
	if (argc > 1)
		device = argv[1];

	std::string device_str = device;
	V4L2Camera cam(device_str, 640, 480);

	if (!cam.init() || !cam.start()) {
		std::cerr << "Failed to initialize camera" << std::endl;
		return 1;
	}

	cv::namedWindow("Preview", cv::WINDOW_AUTOSIZE);

	int frame_count = 0;
	auto start_time = std::chrono::steady_clock::now();
	double fps = 0.0;

	while (true) {
		cv::Mat frame;
		if (!cam.getFrame(frame))
			break;

		frame_count++;
		auto now = std::chrono::steady_clock::now();
		double elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - start_time).count() / 1000.0;
		if (elapsed >= 1.0) {
			fps = frame_count / elapsed;
			start_time = now;
			frame_count = 0;
		}

		char fps_text[32];
		snprintf(fps_text, sizeof(fps_text), "FPS: %.1f", fps);
		cv::putText(frame, fps_text, cv::Point(10, 30),
		            cv::FONT_HERSHEY_SIMPLEX, 0.8, cv::Scalar(0, 255, 0), 2);

		cv::imshow("Preview", frame);
		if (cv::waitKey(1) == 27)
			break;
	}

	return 0;
}

