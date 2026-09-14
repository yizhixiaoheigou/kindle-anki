@echo off
REM Double-click on Windows to open the Kindle Anki converter.
cd /d "%~dp0\.."
if exist "dist\Kindle-Anki-Import\Kindle-Anki-Import.exe" (
  "dist\Kindle-Anki-Import\Kindle-Anki-Import.exe"
  goto :eof
)
where py >nul 2>&1
if %ERRORLEVEL%==0 (
  py -3 tools\kindle_import_app.py
  goto :eof
)
where python >nul 2>&1
if %ERRORLEVEL%==0 (
  python tools\kindle_import_app.py
  goto :eof
)
echo Need Python 3. Install it from https://www.python.org/downloads/ then double-click this file again.
pause
