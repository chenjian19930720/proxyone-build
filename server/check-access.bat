@echo off
chcp 65001 >nul
title 待续IP后台 · 访问自检
cd /d "%~dp0"

echo.
echo ============================================================
echo   待续IP系统 · 后台访问自检
echo ============================================================
echo.

echo [1] 服务进程
tasklist /fi "imagename eq python.exe" 2>nul | findstr /i python.exe
echo.

echo [2] 端口 8787
netstat -ano | findstr ":8787" | findstr LISTENING
echo.

echo [3] 本机地址（这个一定能开）
echo     http://127.0.0.1:8787
echo.

echo [4] 局域网地址（手机要连同一个 WiFi 才能开）
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /i "IPv4"') do (
    for /f "tokens=* delims= " %%b in ("%%a") do echo     http://%%b:8787
)
echo.

echo [5] 用浏览器打开
start "" "http://127.0.0.1:8787"
echo.

echo ============================================================
echo 打不开时按顺序检查：
echo   1. 手机和电脑是不是连的同一个路由器（IP 前三段要一样）
echo   2. 手机上有没有开着机场/VPN —— 先关掉，代理会把 192.168 的地址也带走
echo   3. 电脑上有没有开 SSTap/Clash 之类的全局代理 —— 先退出
echo   4. Windows 防火墙弹窗要点「允许访问」
echo ============================================================
echo.
pause
