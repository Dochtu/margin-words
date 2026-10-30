@echo off
cd /d "%~dp0"
title wordbook agent - port 8787

rem Prefer the project virtualenv so dependencies come from the same Python.
set "PY=python"
if exist ".venv\Scripts\python.exe" set "PY=.venv\Scripts\python.exe"

echo ==========================================
echo   Wordbook Agent  (LangGraph)
echo ==========================================
echo.

echo [1/3] Checking dependencies...
"%PY%" -c "import fastapi, uvicorn, langgraph, langchain_openai" 2>nul
if errorlevel 1 goto install
echo       dependencies OK
goto checkenv

:install
echo       installing requirements.txt ...
"%PY%" -m pip install -r requirements.txt
if errorlevel 1 goto pipfail
echo       install finished

:checkenv
echo [2/3] Checking model config...
if not exist ".env" (
  echo       .env not found; running in mock mode
) else (
  echo       .env found
)

echo [3/3] Starting server...
echo.
echo   Local:  http://127.0.0.1:8787
for /f "delims=" %%i in ('%PY% lan_ip.py') do set LANIP=%%i
echo   LAN:    http://%LANIP%:8787
echo.
echo   App agent URL is compiled from config/app_config.json
echo   and must match the LAN address above.
echo   The phone must be on the same Wi-Fi; adb reverse is NOT needed.
echo   If the PC IP changes, edit config/app_config.json and
echo   lib/core/app_config.dart, then rebuild the app.
echo.
echo   Close this window to stop the server.
echo ------------------------------------------
"%PY%" -m uvicorn app:app --host 0.0.0.0 --port 8787
goto end

:pipfail
echo.
echo Install failed. Check network / Python version.
echo Manual: "%PY%" -m pip install -r requirements.txt
echo Mirror: "%PY%" -m pip install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
pause
exit /b 1

:end
echo.
echo Server stopped.
pause
