@echo off
echo ============================================
echo  Insurance Exam APP - Build Script
echo ============================================
echo.

:: Set required environment variables
set JAVA_HOME=C:\Program Files\Android\Android Studio\jbr
set ANDROID_HOME=C:\Users\%USERNAME%\AppData\Local\Android\Sdk
set ANDROID_SDK_ROOT=%ANDROID_HOME%
set FLUTTER_HOME=C:\src\flutter
set PATH=%FLUTTER_HOME%\bin;%JAVA_HOME%\bin;%ANDROID_HOME%\cmdline-tools\latest\bin;%ANDROID_HOME%\platform-tools;%PATH%

:: Change to script directory
cd /d "%~dp0"

:: Check Flutter
flutter --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Flutter not found at %FLUTTER_HOME%
    echo Please verify Flutter is installed at C:\src\flutter
    pause & exit /b 1
)

echo [Step 1/5] Creating Android scaffold...
flutter create . --project-name insurance_exam_app --org com.exammaster --platforms android
if errorlevel 1 (
    echo [INFO] flutter create error - safe to ignore if project files already exist.
)

echo [Step 2/5] Getting packages...
flutter pub get
if errorlevel 1 (
    echo [ERROR] flutter pub get failed
    pause & exit /b 1
)

echo [Step 3/5] Cleaning cache...
flutter clean
flutter pub get

echo [Step 4/5] Building Debug APK...
flutter build apk --debug
if errorlevel 1 goto :build_error

echo [Step 5/5] Building Release APK...
flutter build apk --release
if errorlevel 1 goto :build_error

echo.
echo ============================================
echo  BUILD SUCCESS!
echo ============================================
echo.
echo APK locations:
echo   Release: build\app\outputs\flutter-apk\app-release.apk
echo   Debug:   build\app\outputs\flutter-apk\app-debug.apk
echo.
echo Install via USB (requires USB debugging on phone):
echo   adb install build\app\outputs\flutter-apk\app-release.apk
echo.
echo Or copy app-release.apk to your phone and tap to install.
echo.
pause
exit /b 0

:build_error
echo.
echo [ERROR] APK build failed. Common fixes:
echo   1. Check Java:    java -version
echo   2. Check Android: flutter doctor
echo   3. Manual fix:    flutter clean
echo.
pause
exit /b 1
