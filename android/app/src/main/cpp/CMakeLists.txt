cmake_minimum_required(VERSION 3.22.1)
project(micro_usb_audio LANGUAGES C)

add_library(micro_usb_audio SHARED usb_pcm_writer.c usb_functionfs_hid.c)
target_compile_features(micro_usb_audio PRIVATE c_std_11)
target_compile_options(micro_usb_audio PRIVATE -Wall -Wextra -Werror)
target_link_libraries(micro_usb_audio PRIVATE dl)
