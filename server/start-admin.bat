@echo off
chcp 65001 >nul
title 待续IP系统 · 线路后台
cd /d "%~dp0"

echo.
echo ============================================================
echo   待续IP系统 线路后台
echo ============================================================
echo.

where python >nul 2>nul
if errorlevel 1 (
  echo [错误] 没有找到 python，请先安装 Python 3
  echo        下载 https://www.python.org/downloads/
  pause
  exit /b 1
)

echo 正在打开浏览器： http://127.0.0.1:8787
start "" "http://127.0.0.1:8787"

echo.
echo 服务启动中，关闭这个窗口就会停止服务。
echo.
python admin_server.py --port 8787 --user admin --pass admin888

pause
