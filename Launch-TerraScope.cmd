@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%" >nul

where julia >nul 2>nul
if errorlevel 1 (
    echo Julia was not found on PATH.
    echo Install Julia or add it to PATH, then run this launcher again.
    popd >nul
    exit /b 1
)

set "SYSIMAGE=build\TerraScopeSysimage.dll"
set "PROJECT_ARG=--project=."
set "ENTRYPOINT=examples\launch_TerraScope3D.jl"

echo TerraScope launcher is starting.
echo Keep this window open; startup progress appears here until the viewer is ready.
echo.

if exist "%SYSIMAGE%" (
    echo Launching TerraScope with the prebuilt sysimage...
    echo Loading Julia and TerraScope. The progress bar will appear shortly...
    julia %PROJECT_ARG% -J "%SYSIMAGE%" "%ENTRYPOINT%"
    set "EXITCODE=%ERRORLEVEL%"
    popd >nul
    exit /b %EXITCODE%
)

echo TerraScope sysimage not found at "%SYSIMAGE%".
set /p BUILD_NOW=Build it now for faster future launches? [Y/n]: 
if /i "%BUILD_NOW%"=="n" goto launch_without_sysimage
if /i "%BUILD_NOW%"=="no" goto launch_without_sysimage

echo Building TerraScope sysimage. This can take several minutes...
julia %PROJECT_ARG% scripts\build_sysimage.jl
if errorlevel 1 (
    echo Sysimage build failed. Launching without sysimage.
    goto launch_without_sysimage
)

if exist "%SYSIMAGE%" (
    echo Sysimage build completed.
    julia %PROJECT_ARG% -J "%SYSIMAGE%" "%ENTRYPOINT%"
    set "EXITCODE=%ERRORLEVEL%"
    popd >nul
    exit /b %EXITCODE%
)

:launch_without_sysimage
echo Launching TerraScope without a sysimage...
echo Loading Julia and TerraScope. The progress bar will appear shortly...
julia %PROJECT_ARG% "%ENTRYPOINT%"
set "EXITCODE=%ERRORLEVEL%"
popd >nul
exit /b %EXITCODE%