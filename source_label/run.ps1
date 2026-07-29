# 피자소스 유효기한 스마트 라벨링 시스템 실행기
Clear-Host
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   피자소스 유효기한 스마트 라벨링 시스템 실행기   " -ForegroundColor Yellow
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "로컬 브라우저에서 시스템을 실행합니다..." -ForegroundColor Green
Write-Host ""
Write-Host "위치: $PSScriptRoot\index.html" -ForegroundColor Gray
Write-Host ""

$Path = Join-Path $PSScriptRoot "index.html"
Start-Process $Path

Write-Host "성공적으로 실행되었습니다!" -ForegroundColor Green
