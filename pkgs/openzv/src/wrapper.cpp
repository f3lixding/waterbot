#include <cstdint>
#include <cstring>
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

extern "C" int openzv_opencv_version_major() {
    return CV_VERSION_MAJOR;
}

extern "C" int openzv_bgr_to_gray(
    const std::uint8_t* input_bgr,
    int width,
    int height,
    std::uint8_t* output_gray
) {
    if (input_bgr == nullptr || output_gray == nullptr || width <= 0 || height <= 0) {
        return 1;
    }

    try {
        cv::Mat input(height, width, CV_8UC3, const_cast<std::uint8_t*>(input_bgr));
        cv::Mat gray;
        cv::cvtColor(input, gray, cv::COLOR_BGR2GRAY);
        std::memcpy(output_gray, gray.data, static_cast<std::size_t>(width * height));
        return 0;
    } catch (const cv::Exception&) {
        return 2;
    }
}
