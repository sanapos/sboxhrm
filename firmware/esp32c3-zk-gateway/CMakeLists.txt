cmake_minimum_required(VERSION 3.16)

set(ENV{IDF_TARGET} esp32c3)

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(zk_gateway)
