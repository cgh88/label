@echo off
chcp 65001 > nul
echo [PapaLabel] 윈도우 시작프로그램 등록 해제 중...
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "PapaLabel" /f
if %ERRORLEVEL% equ 0 (
    echo [성공] 윈도우 시작프로그램에서 정상적으로 해제되었습니다.
) else (
    echo [안내] 이미 등록되어 있지 않거나 해제되었습니다.
)
pause
