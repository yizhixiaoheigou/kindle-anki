@echo off
rem Build the Windows converter onedir: dist\Kindle-Anki-Import\Kindle-Anki-Import.exe
rem Needs Python 3 (with Tcl/Tk) from python.org. Everything stays local.
rem Pass -y to skip the interactive pauses (unattended runs).
setlocal
cd /d "%~dp0.."

set NOPAUSE=0
if /i "%~1"=="-y" set NOPAUSE=1

where py >nul 2>&1
if not %ERRORLEVEL%==0 (
  echo Need Python 3 from https://www.python.org/downloads/ with Tcl/Tk.
  if "%NOPAUSE%"=="0" pause
  exit /b 1
)

if exist .venv-windows goto :have_venv
py -3 -m venv .venv-windows
if errorlevel 1 goto :fail
:have_venv

rem Some Python installs cannot auto-discover their Tcl data directory (init.tcl),
rem which makes PyInstaller silently drop tkinter from the bundle. Point Tcl at the
rem data directories explicitly before anything imports tkinter.
for /f "delims=" %%i in ('.venv-windows\Scripts\python.exe -c "import sys, os; print(os.path.join(sys.base_prefix, 'tcl', 'tcl8.6'))"') do set "TCL_LIBRARY=%%i"
for /f "delims=" %%i in ('.venv-windows\Scripts\python.exe -c "import sys, os; print(os.path.join(sys.base_prefix, 'tcl', 'tk8.6'))"') do set "TK_LIBRARY=%%i"

rem Gate 1: the build interpreter must bring up a real Tcl interpreter.
.venv-windows\Scripts\python.exe -c "import tkinter; tkinter.Tcl(); print('tkinter OK', tkinter.TkVersion)"
if errorlevel 1 (
  echo Build Python cannot initialize Tcl/Tk. Reinstall Python from python.org keeping "tcl/tk and IDLE" enabled, then delete .venv-windows and retry.
  goto :fail
)

.venv-windows\Scripts\python.exe -m pip install --disable-pip-version-check -r requirements-dev.txt
if errorlevel 1 goto :fail
.venv-windows\Scripts\pyinstaller.exe --noconfirm --clean --distpath dist --workpath build\windows packaging\kindleanki.spec
if errorlevel 1 goto :fail

rem Gate 2: tkinter must actually be inside the bundle.
if not exist "dist\Kindle-Anki-Import\_internal\_tkinter.pyd" (
  echo Build finished but _tkinter.pyd is missing from the bundle; check build\windows\kindleanki\warn-kindleanki.txt
  goto :fail
)

echo.
echo Done: dist\Kindle-Anki-Import\Kindle-Anki-Import.exe
if "%NOPAUSE%"=="0" pause
exit /b 0

:fail
echo Build failed.
if "%NOPAUSE%"=="0" pause
exit /b 1
