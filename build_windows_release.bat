@echo off
chcp 65001 > nul
echo ====================================================
echo [PapaLabel] Windows 릴리즈 빌드 및 배포 파일 생성기
echo ====================================================

cd /d "%~dp0client_flutter"
echo [1/4] Flutter 종속성 확인 및 패키지 가져오기...
call flutter pub get
if %ERRORLEVEL% neq 0 (
    echo [오류] flutter pub get 실패
    pause
    exit /b 1
)

echo [2/4] Windows Release 빌드 진행 중...
call flutter build windows --release
if %ERRORLEVEL% neq 0 (
    echo [오류] flutter build windows 실패
    pause
    exit /b 1
)

cd /d "%~dp0"
echo [3/4] 배포 폴더 구성 중...
if not exist "release_windows\PapaLabel_Windows" mkdir "release_windows\PapaLabel_Windows"
xcopy /E /I /Y "client_flutter\build\windows\x64\runner\Release\*" "release_windows\PapaLabel_Windows\"

echo [4/4] 배포용 ZIP 파일 생성 중...
powershell -Command "Compress-Archive -Path 'release_windows\PapaLabel_Windows' -DestinationPath 'files\PapaLabel_Windows_Release.zip' -Force; Copy-Item 'files\PapaLabel_Windows_Release.zip' 'release_windows\PapaLabel_Windows_v1.1.1.zip' -Force"

echo ====================================================
echo [완료] Windows 배포 파일이 성공적으로 생성되었습니다!
echo  - 배포 실행 폴더: release_windows\PapaLabel_Windows\
echo  - 웹 배포 ZIP   : files\PapaLabel_Windows_Release.zip
echo  - 릴리즈 압축본 : release_windows\PapaLabel_Windows_v1.1.1.zip
echo ====================================================
pause
