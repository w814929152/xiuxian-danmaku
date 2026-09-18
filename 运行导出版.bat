@echo off
chcp 936 >nul
setlocal
set "EXE=%~dp0build\弹幕修仙.exe"

if not exist "%EXE%" (
  echo(
  echo   [!] 找不到导出版：%EXE%
  echo(
  echo   先在 Godot 里执行：项目 - 导出 - Windows Desktop
  echo   或命令行：Godot_console --headless --path "%~dp0" --export-release "Windows Desktop"
  echo(
  pause
  exit /b 1
)

echo   启动导出版：%EXE%
echo   提示：这是打包好的版本，不含尚未重新导出的最新改动。
echo(
start "" "%EXE%"
endlocal
exit /b 0
