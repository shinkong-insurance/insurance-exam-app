@echo off
chcp 65001 > nul
echo ============================================
echo  Insurance Exam - Build Web + Deploy
echo ============================================

set FLUTTER_HOME=C:\src\flutter
set PATH=%FLUTTER_HOME%\bin;%PATH%

cd /d "%~dp0"

echo [1/4] flutter pub get...
flutter pub get
if errorlevel 1 ( echo FAILED pub get & pause & exit /b 1 )

echo [2/4] flutter build web --release...
flutter build web --release --base-href /insurance-exam-app/
if errorlevel 1 ( echo FAILED build web & pause & exit /b 1 )

echo [3/4] Copying admin.html to build/web...
copy /Y "web\admin.html" "build\web\admin.html"

echo [4/4] Git commit + push to gh-pages...
cd build\web
git init
git checkout -b gh-pages 2>nul || git checkout gh-pages
git add -A
git commit -m "deploy: web auth v2 - national ID + DOB login"
git remote remove origin 2>nul
git remote add origin https://github.com/shinkong-insurance/insurance-exam-app.git
git push -f origin gh-pages
cd ..\..

echo.
echo ============================================
echo  DONE! https://shinkong-insurance.github.io/insurance-exam-app/
echo  Admin: https://shinkong-insurance.github.io/insurance-exam-app/admin.html
echo ============================================
pause
