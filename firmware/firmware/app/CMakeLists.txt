cmake_minimum_required(VERSION 3.20.0)

# ---------------------------------------------------------------------------
# IronLoop Firmware — Complete Build
# Target board : Seeed XIAO nRF52840 Sense (xiao_ble/nrf52840/sense)
# ---------------------------------------------------------------------------

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(ironloop_firmware)

target_sources(app PRIVATE
    src/main.c
    src/drivers/imu.c
    src/drivers/led_indicator.c
    src/drivers/battery.c
    src/drivers/button.c
    src/ble/ble_protocol.c
    src/ble/ble_service.c
    src/sensor/calibration.c
    src/sensor/fifo.c
    src/app/session_lite.c
)

target_include_directories(app PRIVATE
    src
)
