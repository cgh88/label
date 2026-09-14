@echo off
chcp 65001 > nul
echo ====================================================
echo [PapaLabel] Android APK 릴리즈 빌드 및 태블릿 설치기
echo ====================================================

echo [1/4] 배포 버전 및 빌드 일시 자동 기록 중...
call node "%~dp0scripts\update-app-version.js"
if %ERRORLEVEL% neq 0 (
    echo [오류] 버전 자동 생성 실패
    pause
    exit /b 1
)

cd /d "%~dp0client_flutter"
echo [2/4] Flutter 종속성 확인 및 패키지 가져오기...
call flutter pub get
if %ERRORLEVEL% neq 0 (
    echo [오류] flutter pub get 실패
    pause
    exit /b 1
)

echo [3/4] Android Release APK 빌드 진행 중...
call flutter build apk --release
if %ERRORLEVEL% neq 0 (
    echo [오류] flutter build apk 실패
    pause
    exit /b 1
)

cd /d "%~dp0"
echo [4/4] 웹 서버 다운로드 파일 갱신 및 태블릿 설치 확인...
powershell -Command "Copy-Item -Path 'client_flutter\build\app\outputs\flutter-apk\app-release.apk' -Destination 'files\app-release.apk' -Force"

if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" (
    echo ADB 연결 기기 확인 및 자동 설치 시도 중...
    "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" install -r "client_flutter\build\app\outputs\flutter-apk\app-release.apk"
)

echo ====================================================
echo [완료] Android 배포 파일이 성공적으로 생성되었습니다!
echo  - APK 파일: files\app-release.apk
echo ====================================================
pause
