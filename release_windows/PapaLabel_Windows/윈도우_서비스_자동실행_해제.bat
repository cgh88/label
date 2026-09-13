@echo off
chcp 65001 > nul
echo ====================================================
echo [PapaLabel] 윈도우 서비스(작업 스케줄러) 등록 해제
echo ====================================================

net session >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [경고] 관리자 권한으로 실행해 주세요. (마우스 우클릭 -> 관리자 권한으로 실행)
    pause
    exit /b 1
)

schtasks /delete /tn "PapaLabelService" /f
if %ERRORLEVEL% equ 0 (
    echo.
    echo [성공] PapaLabel 서비스가 정상적으로 해제되었습니다.
) else (
    echo.
    echo [안내] 등록된 작업이 없거나 이미 해제되었습니다.
)
pause
