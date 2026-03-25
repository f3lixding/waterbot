#include <cstdint>
#include <cstring>
#include <vector>
#include <opencv2/core.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

struct OpenZvImageSize {
    int width;
    int height;
};

struct OpenZvHsvRange {
    std::uint8_t h_min;
    std::uint8_t s_min;
    std::uint8_t v_min;
    std::uint8_t h_max;
    std::uint8_t s_max;
    std::uint8_t v_max;
};

struct OpenZvBlobCircle {
    float center_x;
    float center_y;
    float radius;
    float area;
};

extern "C" int openzv_opencv_version_major() {
    return CV_VERSION_MAJOR;
}

extern "C" int openzv_jpeg_info(
    const std::uint8_t* input_jpeg,
    std::size_t input_len,
    OpenZvImageSize* output_size
) {
    if (input_jpeg == nullptr || output_size == nullptr || input_len == 0) {
        return 1;
    }

    try {
        cv::Mat encoded(1, static_cast<int>(input_len), CV_8UC1, const_cast<std::uint8_t*>(input_jpeg));
        cv::Mat decoded = cv::imdecode(encoded, cv::IMREAD_COLOR);
        if (decoded.empty()) {
            return 2;
        }

        output_size->width = decoded.cols;
        output_size->height = decoded.rows;
        return 0;
    } catch (const cv::Exception&) {
        return 3;
    }
}

extern "C" int openzv_decode_jpeg_to_bgr(
    const std::uint8_t* input_jpeg,
    std::size_t input_len,
    int width,
    int height,
    std::uint8_t* output_bgr
) {
    if (input_jpeg == nullptr || output_bgr == nullptr || input_len == 0 || width <= 0 || height <= 0) {
        return 1;
    }

    try {
        cv::Mat encoded(1, static_cast<int>(input_len), CV_8UC1, const_cast<std::uint8_t*>(input_jpeg));
        cv::Mat decoded = cv::imdecode(encoded, cv::IMREAD_COLOR);
        if (decoded.empty() || decoded.cols != width || decoded.rows != height) {
            return 2;
        }

        std::memcpy(output_bgr, decoded.data, static_cast<std::size_t>(width * height * 3));
        return 0;
    } catch (const cv::Exception&) {
        return 3;
    }
}

extern "C" int openzv_yuyv_to_bgr(
    const std::uint8_t* input_yuyv,
    int width,
    int height,
    std::uint8_t* output_bgr
) {
    if (input_yuyv == nullptr || output_bgr == nullptr || width <= 0 || height <= 0) {
        return 1;
    }

    try {
        cv::Mat input(height, width, CV_8UC2, const_cast<std::uint8_t*>(input_yuyv));
        cv::Mat bgr;
        cv::cvtColor(input, bgr, cv::COLOR_YUV2BGR_YUYV);
        std::memcpy(output_bgr, bgr.data, static_cast<std::size_t>(width * height * 3));
        return 0;
    } catch (const cv::Exception&) {
        return 2;
    }
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

extern "C" int openzv_bgr_to_hsv(
    const std::uint8_t* input_bgr,
    int width,
    int height,
    std::uint8_t* output_hsv
) {
    if (input_bgr == nullptr || output_hsv == nullptr || width <= 0 || height <= 0) {
        return 1;
    }

    try {
        cv::Mat input(height, width, CV_8UC3, const_cast<std::uint8_t*>(input_bgr));
        cv::Mat hsv;
        cv::cvtColor(input, hsv, cv::COLOR_BGR2HSV);
        std::memcpy(output_hsv, hsv.data, static_cast<std::size_t>(width * height * 3));
        return 0;
    } catch (const cv::Exception&) {
        return 2;
    }
}

extern "C" int openzv_hsv_in_range(
    const std::uint8_t* input_hsv,
    int width,
    int height,
    OpenZvHsvRange range,
    std::uint8_t* output_mask
) {
    if (input_hsv == nullptr || output_mask == nullptr || width <= 0 || height <= 0) {
        return 1;
    }

    try {
        cv::Mat input(height, width, CV_8UC3, const_cast<std::uint8_t*>(input_hsv));
        cv::Mat mask;
        cv::inRange(
            input,
            cv::Scalar(range.h_min, range.s_min, range.v_min),
            cv::Scalar(range.h_max, range.s_max, range.v_max),
            mask
        );
        std::memcpy(output_mask, mask.data, static_cast<std::size_t>(width * height));
        return 0;
    } catch (const cv::Exception&) {
        return 2;
    }
}

extern "C" int openzv_find_largest_blob_circle(
    const std::uint8_t* input_mask,
    int width,
    int height,
    float min_area,
    OpenZvBlobCircle* output_circle
) {
    if (input_mask == nullptr || output_circle == nullptr || width <= 0 || height <= 0 || min_area < 0.0f) {
        return 2;
    }

    try {
        cv::Mat mask(height, width, CV_8UC1, const_cast<std::uint8_t*>(input_mask));
        std::vector<std::vector<cv::Point>> contours;
        cv::findContours(mask.clone(), contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);

        double best_area = -1.0;
        std::vector<cv::Point> best_contour;
        for (const auto& contour : contours) {
            const double area = cv::contourArea(contour);
            if (area >= static_cast<double>(min_area) && area > best_area) {
                best_area = area;
                best_contour = contour;
            }
        }

        if (best_contour.empty()) {
            return 1;
        }

        cv::Point2f center;
        float radius = 0.0f;
        cv::minEnclosingCircle(best_contour, center, radius);
        output_circle->center_x = center.x;
        output_circle->center_y = center.y;
        output_circle->radius = radius;
        output_circle->area = static_cast<float>(best_area);
        return 0;
    } catch (const cv::Exception&) {
        return 2;
    }
}
