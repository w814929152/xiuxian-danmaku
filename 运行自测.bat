@echo off
chcp 936 >nul
setlocal
set "GODOT="

rem ---- 自测要控制台版才有输出，优先找 console 版 ----
if defined GODOT_EXE call :try "%GODOT_EXE%"
call :try "%USERPROFILE%\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
call :try "%~dp0Godot_console.exe"
call :try "%USERPROFILE%\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
call :try "C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe"
if not defined GODOT for /f "delims=" %%P in ('where godot 2^>nul') do call :try "%%P"

if not defined GODOT (
  echo(
  echo   [!] 找不到 Godot console 版可执行文件
  echo(
  echo   请用记事本打开本文件，照抄一行：
  echo       call :try "你的完整路径\Godot_xxx_console.exe"
  echo(
  pause
  exit /b 1
)

echo   使用 Godot：%GODOT%
echo   判定标准：fails=0 且日志中 ERROR / WARNING 均为 0
echo(
"%GODOT%" --headless --path "%~dp0" --quit-after 4000 "res://_selftest/SelfTest.tscn"
echo(
pause
endlocal
exit /b 0

:try
if defined GODOT exit /b 0
if "%~1"=="" exit /b 0
if exist "%~1" set "GODOT=%~1"
exit /b 0
