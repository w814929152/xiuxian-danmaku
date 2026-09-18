@echo off
chcp 936 >nul
setlocal
set "GODOT="

rem ---- 依次尝试：环境变量 -> 本目录 -> 常见安装位置 -> PATH ----
if defined GODOT_EXE call :try "%GODOT_EXE%"
call :try "%~dp0Godot.exe"
call :try "%USERPROFILE%\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
call :try "%LOCALAPPDATA%\Programs\Godot\Godot_v4.7.2-stable_win64.exe"
call :try "C:\Program Files\Godot\Godot_v4.7.2-stable_win64.exe"
if not defined GODOT for /f "delims=" %%P in ('where godot 2^>nul') do call :try "%%P"

if not defined GODOT (
  echo(
  echo   [!] 找不到 Godot 可执行文件
  echo(
  echo   任选一种方式指路：
  echo     1. 设置环境变量 GODOT_EXE 指向 Godot.exe
  echo     2. 把 Godot.exe 复制到本 bat 所在目录
  echo     3. 用记事本打开本文件，照抄一行 call :try "你的完整路径\Godot.exe"
  echo(
  pause
  exit /b 1
)

echo   使用 Godot：%GODOT%
echo   项目目录：%~dp0
echo(
"%GODOT%" --path "%~dp0"
endlocal
exit /b 0

:try
if defined GODOT exit /b 0
if "%~1"=="" exit /b 0
if exist "%~1" set "GODOT=%~1"
exit /b 0
