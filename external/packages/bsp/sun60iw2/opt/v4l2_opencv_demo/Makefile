CXX := g++
CXXFLAGS := -Wall -O2 `pkg-config --cflags opencv4`
LDFLAGS := `pkg-config --libs opencv4`

SRC := v4l2_camera.cpp test_camera.cpp
TARGET := cam_test

all: $(TARGET)

$(TARGET): $(SRC)
	$(CXX) $(CXXFLAGS) -o $@ $^ $(LDFLAGS)

PYTHON_MODULE := v4l2cam$(shell python3-config --extension-suffix)
PYBIND11_FLAGS := `python3 -m pybind11 --includes`
PYTHON_LIBS := `python3-config --ldflags`

python_module: v4l2_camera_bind.cpp v4l2_camera.cpp
	$(CXX) $(CXXFLAGS) -O2 -Wall -shared -fPIC $(PYBIND11_FLAGS) -o $(PYTHON_MODULE) $^ $(LDFLAGS) $(PYTHON_LIBS)

.PHONY: all clean python_module

clean:
	rm -f $(TARGET) $(PYTHON_MODULE)
