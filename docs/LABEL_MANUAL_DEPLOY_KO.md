# 라벨 서버 수동 배포 매뉴얼

이 문서는 `labelprint.pji.co.kr` 라벨 서버에 새 소스 코드를 올리는 방법입니다.
명령어는 한 번에 한 줄씩 복사해서 실행하세요.

## 먼저 준비할 것

- Windows PC
- 이 프로젝트 폴더: `D:\DEV\aiCoding\label`
- AWS Lightsail SSH 키:
  `D:\바탕TEMP\180308바탕화면폴더\클라우드신청서\메가존\papa_lightsails\LightsailDefaultKey-ap-northeast-2.pem`
- 서버 주소: `54.180.136.194`

주의: 아래 명령어에서 `server.js`는 서버 프로그램입니다. 데이터베이스와 비밀번호 파일은 올리지 않습니다.

## 1. 프로젝트 폴더 열기

PowerShell을 열고 다음을 실행합니다.

```powershell
cd D:\DEV\aiCoding\label
```

## 2. 내 컴퓨터에서 테스트하기

```powershell
npm.cmd test
```

마지막에 다음처럼 나오면 통과입니다.

```text
pass 10
fail 0
```

`fail`이 0이 아니면 배포하지 말고 개발 담당자에게 알려주세요.

## 3. 서버에 새 파일 보내기

아래 명령어를 그대로 실행합니다.

```powershell
$key='D:\바탕TEMP\180308바탕화면폴더\클라우드신청서\메가존\papa_lightsails\LightsailDefaultKey-ap-northeast-2.pem'
$scp='C:\Program Files\Git\usr\bin\scp.exe'
& $scp -F /dev/null -i $key -o IdentitiesOnly=yes server.js ubuntu@54.180.136.194:/tmp/papa-label-server.js
```

화면에 오류가 없으면 파일 전송이 끝난 것입니다.

## 4. 서버에서 백업하고 재시작하기

다음 명령어를 실행합니다. 기존 파일을 날짜와 함께 백업한 뒤 새 파일을 설치합니다.

```powershell
$ssh='C:\Program Files\Git\usr\bin\ssh.exe'
& $ssh -F /dev/null -i $key -o IdentitiesOnly=yes ubuntu@54.180.136.194 'set -e; sudo cp /opt/papa-label/server.js /opt/papa-label/server.js.bak-$(date +%Y%m%d-%H%M%S); sudo install -o label-server -g label-server -m 0640 /tmp/papa-label-server.js /opt/papa-label/server.js; sudo systemctl restart label-server; sleep 2; sudo systemctl is-active label-server'
```

마지막 줄에 `active`가 나오면 서버가 켜진 것입니다.

## 5. 인터넷에서 확인하기

```powershell
Invoke-WebRequest https://labelprint.pji.co.kr/api/health -UseBasicParsing
```

상태 코드가 `200`이면 정상입니다.

로그인하지 않은 상태에서 아래 API가 `401`이면 보안 보호도 정상입니다.

```powershell
Invoke-WebRequest https://labelprint.pji.co.kr/api/sync/database -UseBasicParsing
```

PowerShell이 오류처럼 보여도 응답 상태가 `401`이면 정상입니다. `401`은 “로그인이 필요하다”는 뜻입니다.

## 문제가 생겼을 때 되돌리기

배포 후 `active`가 나오지 않거나 홈페이지가 열리지 않으면, 서버의 가장 최근 백업으로 되돌립니다.

```powershell
& $ssh -F /dev/null -i $key -o IdentitiesOnly=yes ubuntu@54.180.136.194 'set -e; backup=$(sudo ls -t /opt/papa-label/server.js.bak-* | head -1); sudo cp "$backup" /opt/papa-label/server.js; sudo chown label-server:label-server /opt/papa-label/server.js; sudo chmod 0640 /opt/papa-label/server.js; sudo systemctl restart label-server; sudo systemctl is-active label-server'
```

## 절대로 하면 안 되는 것

- `/opt/papa-label/database.sqlite`를 삭제하거나 덮어쓰지 마세요.
- `/etc/papa-label.env` 파일을 삭제하거나 다른 사람에게 보여주지 마세요.
- Lightsail 방화벽에서 `3100` 포트를 외부에 열지 마세요. 외부 접속은 HTTPS 443 포트만 사용합니다.
- SSH 키 파일을 카카오톡, 이메일, GitHub 등에 올리지 마세요.

## 배포가 끝난 뒤 확인할 목록

- [ ] `npm.cmd test` 결과가 `fail 0`
- [ ] 서버 상태가 `active`
- [ ] `https://labelprint.pji.co.kr` 접속 가능
- [ ] `/api/health` 응답이 200
- [ ] 로그인 없이 `/api/sync/database` 응답이 401
- [ ] 기존 라벨·재고 데이터가 그대로 보임
