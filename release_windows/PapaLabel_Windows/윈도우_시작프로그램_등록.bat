@echo off
chcp 65001 > nul
echo [PapaLabel] 윈도우 시작프로그램(부팅 시 자동 실행) 등록 중...
set "TARGET_PATH=%~dp0client_flutter.exe"
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "PapaLabel" /t REG_SZ /d "\"%TARGET_PATH%\"" /f
if %ERRORLEVEL% equ 0 (
    echo [성공] 윈도우 부팅 시 PapaLabel 라벨 프린터 클라이언트가 자동 시작되도록 등록되었습니다.
) else (
    echo [오류] 등록에 실패했습니다. 관리자 권한으로 실행해 주세요.
)
pause
