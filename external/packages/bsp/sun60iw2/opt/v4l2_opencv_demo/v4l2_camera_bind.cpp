#include <pybind11/pybind11.h>
#include <pybind11/numpy.h>
#include "v4l2_camera.h"

namespace py = pybind11;

class PyCamera
{
public:
	PyCamera(const std::string& device, const int width, const int hight) : cam_(device, width, hight)
	{
		//std::cout << "[PyCamera] Device passed: " << device << std::endl;
	}

	bool init()
	{
		return cam_.init();
	}
	bool start()
	{
		return cam_.start();
	}
	bool stop()
	{
		return cam_.stop();
	}

	py::array_t<uint8_t> get_frame()
	{
		cv::Mat frame;
		if (!cam_.getFrame(frame)) {
			throw std::runtime_error("Failed to get frame");
		}

		py::array_t<uint8_t> array({frame.rows, frame.cols, frame.channels()}, frame.data);
		return array;
	}

private:
	V4L2Camera cam_;
};

PYBIND11_MODULE(v4l2cam, m)
{
	py::class_<PyCamera>(m, "V4L2Camera")
	.def(py::init<const std::string&, const int, const int>())
	.def("init", &PyCamera::init)
	.def("start", &PyCamera::start)
	.def("stop", &PyCamera::stop)
	.def("get_frame", &PyCamera::get_frame);
}

