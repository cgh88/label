@echo off
chcp 65001 > nul
echo ====================================================
echo [PapaLabel] 윈도우 서비스(작업 스케줄러 자동 실행) 등록
echo ====================================================
set "EXE_PATH=%~dp0client_flutter.exe"

net session >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [경고] 관리자 권한으로 실행해 주세요. (마우스 우클릭 -> 관리자 권한으로 실행)
    pause
    exit /b 1
)

schtasks /create /tn "PapaLabelService" /tr "\"%EXE_PATH%\"" /sc onlogon /rl highest /f
if %ERRORLEVEL% equ 0 (
    echo.
    echo [성공] 윈도우 로그인 시 PapaLabel이 최고 권한으로 자동 실행되도록 등록되었습니다.
) else (
    echo.
    echo [오류] 서비스 등록에 실패했습니다.
)
pause
