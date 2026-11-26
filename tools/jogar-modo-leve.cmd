@echo off
setlocal

if not exist "%~dp0TheLastContract.exe" (
    echo Coloque este arquivo na mesma pasta de TheLastContract.exe.
    pause
    exit /b 1
)

"%~dp0TheLastContract.exe" --rendering-method gl_compatibility --windowed --resolution 1280x720 --max-fps 30 %*
exit /b %errorlevel%
