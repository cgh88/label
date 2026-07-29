# server.ps1
# Native PowerShell Web Server for Pizza Sauce Labeling System
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$port = 9090
$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")

function Send-Response ($response, $contentString, $contentType) {
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($contentString)
    $response.ContentLength64 = $buffer.Length
    $response.ContentType = $contentType
    $response.Headers.Add("Access-Control-Allow-Origin", "*")
    $response.OutputStream.Write($buffer, 0, $buffer.Length)
    $response.OutputStream.Close()
}

try {
    $listener.Start()
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "  피자소스 유효기한 라벨링 서버가 시작되었습니다!" -ForegroundColor Green
    Write-Host "  주소: http://localhost:$port/" -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
    
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        
        $path = $request.Url.LocalPath
        $method = $request.HttpMethod
        
        Write-Host "[$([DateTime]::Now.ToString('HH:mm:ss'))] $method $path" -ForegroundColor Gray
        
        try {
            if ($method -eq "GET" -and ($path -eq "/" -or $path -eq "/index.html")) {
                $filePath = Join-Path $PSScriptRoot "index.html"
                $content = Get-Content $filePath -Raw -Encoding UTF8
                Send-Response $response $content "text/html; charset=utf-8"
            } else {
                $response.StatusCode = 404
                Send-Response $response "Not Found" "text/plain; charset=utf-8"
            }
        }
        catch {
            Write-Host "❌ Error: $_" -ForegroundColor Red
            $response.StatusCode = 500
            Send-Response $response "Internal Error: $_" "text/plain; charset=utf-8"
        }
    }
}
catch {
    if ($_.Exception.Message -like "*already in use*" -or $_.Exception.Message -like "*다른 프로세스*" -or $_.Exception.HResult -eq -2147467259) {
        Write-Host "❌ 포트 $port 번이 이미 사용 중입니다." -ForegroundColor Red
    } else {
        Write-Host "❌ 오류 발생: $_" -ForegroundColor Red
    }
}
finally {
    if ($listener -ne $null) {
        $listener.Close()
        Write-Host "⏹️ Server stopped." -ForegroundColor Yellow
    }
}
