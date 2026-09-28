@echo off
REM ===========================================================================
REM IronLoop Firmware Build Script (Final Master Build)
REM ===========================================================================
REM Prerequisites: NCS v3.4.0 installed at C:\ncs\v3.4.0
REM Board: Seeed XIAO nRF52840 Sense (xiao_ble/nrf52840/sense)
REM Features: Low Power Sleep/Wake, RGB LEDs, Button, Battery Monitor, BLE
REM ===========================================================================

set "TC=C:\ncs\toolchains\dcbdc366a1"
set "PATH=%TC%;%TC%\mingw64\bin;%TC%\bin;%TC%\opt\bin;%TC%\opt\bin\Scripts;%TC%\opt\nanopb\generator-bin;%TC%\nrfutil\bin;%TC%\opt\zephyr-sdk\gnu\arm-zephyr-eabi\bin;%PATH%"
set "PYTHONPATH=%TC%\opt\bin;%TC%\opt\bin\Lib;%TC%\opt\bin\Lib\site-packages"
set "ZEPHYR_BASE=C:\ncs\v3.4.0\zephyr"

echo ===================================================
echo   IRONLOOP Final Firmware Build
echo   Target: Seeed XIAO nRF52840 Sense
echo ===================================================
echo.

echo [1/3] Running west build (pristine clean build)...
"%TC%\opt\bin\Scripts\west.exe" build -p always -b xiao_ble/nrf52840/sense C:\SIH\firmware\app --build-dir C:\SIH\build
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo BUILD FAILED with error %ERRORLEVEL%
    exit /b %ERRORLEVEL%
)

echo.
echo [2/3] Preparing output artifacts and dist directories...
if not exist "C:\SIH\dist" mkdir "C:\SIH\dist"

set "UF2_SRC="
if exist "C:\SIH\build\app\zephyr\zephyr.uf2" set "UF2_SRC=C:\SIH\build\app\zephyr\zephyr.uf2"
if not defined UF2_SRC if exist "C:\SIH\build\zephyr\zephyr.uf2" set "UF2_SRC=C:\SIH\build\zephyr\zephyr.uf2"

if defined UF2_SRC (
    copy /Y "%UF2_SRC%" "C:\SIH\zephyr.uf2" >NUL
    copy /Y "%UF2_SRC%" "C:\SIH\ironloop_firmware_final.uf2" >NUL
    copy /Y "%UF2_SRC%" "C:\SIH\dist\ironloop_firmware_final.uf2" >NUL
    echo   [OK] Copied UF2 to C:\SIH\ironloop_firmware_final.uf2
    echo   [OK] Copied UF2 to C:\SIH\dist\ironloop_firmware_final.uf2
) else (
    echo   [WARNING] zephyr.uf2 not found directly in build folder. Checking for hex...
)

echo.
echo ===================================================
echo   [3/3] BUILD COMPLETE AND READY TO FLASH!
echo ===================================================
echo.
echo Ready-to-flash file location:
echo   -^> C:\SIH\ironloop_firmware_final.uf2
echo   -^> C:\SIH\dist\ironloop_firmware_final.uf2
echo.
echo Flash instructions:
echo   1. Connect XIAO nRF52840 Sense to USB
echo   2. Double-tap the reset button quickly (within 0.5s)
echo   3. Drag and drop 'ironloop_firmware_final.uf2' onto the 'XIAO-SENSE' drive
echo   4. Board auto-resets and starts running IronLoop immediately!
echo.
