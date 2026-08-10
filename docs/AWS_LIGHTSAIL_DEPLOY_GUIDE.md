# 🚀 AWS Lightsail 웹 서버 배포 매뉴얼 (AWS Lightsail Deployment Guide)

본 매뉴얼은 **소비기한 라벨 솔루션 (Node.js/Express 웹 서버)**을 **AWS Lightsail** 클라우드 인스턴스에 설치하고, 24시간 안정적으로 운영하기 위한 단계별 배포 절차를 안내합니다.

---

## 🏗️ 1. AWS Lightsail 인스턴스 생성 및 설정

### 1.1 인스턴스 생성
1. [AWS Lightsail 콘솔](https://lightsail.aws.amazon.com/)에 로그인합니다.
2. **[Create instance]** 버튼을 클릭합니다.
3. **Instance location**: `Seoul (ap-northeast-2)` 선택
4. **Pick your instance image**:
   * Platform: `Linux/Unix`
   * Blueprint: `OS Only` -> `Ubuntu 22.04 LTS` 권장
5. **Choose your instance plan**:
   * 월 $3.50 ~ $5.00 플랜 (1GB RAM / 1 vCPU / 20~40GB SSD) 권장
6. **Identify your instance**: 인스턴스 이름 입력 (예: `shelflife-label-server`)
7. 페이지 하단 **[Create instance]** 클릭하여 인스턴스 생성을 시작합니다.

---

### 1.2 고정 IP (Static IP) 할당
인스턴스가 재부팅되어도 IP 주소가 변경되지 않도록 전용 고정 IP를 할당합니다.
1. Lightsail 콘솔 상단 메뉴에서 **[Networking]** 탭을 클릭합니다.
2. **[Create static IP]** 버튼을 클릭합니다.
3. 방금 생성한 인스턴스(`shelflife-label-server`)를 선택하고 고정 IP 이름을 지정합니다.
4. **[Create]**를 클릭하여 할당받은 Public IP 주소를 메모합니다 (예: `13.125.x.x`).

---

### 1.3 방화벽 포트 개방 (Networking Firewall)
1. 생성한 인스턴스 클릭 -> **[Networking]** 탭으로 이동합니다.
2. **IPv4 Firewall** 항목에서 **[+ Add rule]**을 클릭하여 다음 포트를 개방합니다:
   * **HTTP (Port 80)**: TCP / All IP (`0.0.0.0/0`)
   * **HTTPS (Port 443)**: TCP / All IP (`0.0.0.0/0`)
   * **Custom (Port 3000)**: TCP / All IP (`0.0.0.0/0`) *(직접 포트 접속용)*

---

## 💻 2. 서버 접속 및 환경 구축

### 2.1 SSH 접속
Lightsail 콘솔의 인스턴스 오른쪽 상단 **[Connect using SSH]** 버튼을 클릭하거나, 사용자 터미널에서 접속합니다:
```bash
ssh -i /path/to/your-key.pem ubuntu@<할당받은-고정-IP>
```

### 2.2 시스템 패키지 업데이트 및 Node.js 설치
```bash
# 1. 패키지 목록 업데이트 및 시스템 업그레이드
sudo apt update && sudo apt upgrade -y

# 2. Node.js 18.x LTS 레포지토리 등록 및 설치
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs build-essential git

# 3. 설치 버전 확인
node -v   # v18.x.x 이상 확인
npm -v    # v9.x.x 이상 확인
```

---

## 📦 3. 웹 서버 소스 코드 배치 및 환경 변수 설정

### 3.1 소스 코드 다운로드 및 의존 패키지 설치
```bash
# 1. 홈 디렉터리로 이동 및 저장소 클론
cd ~
git clone https://github.com/cgh88/label.git
cd label

# 2. 프로덕션 패키지 설치 (SQLite3 등 네이티브 모듈 빌드 포함)
npm install --production
```

### 3.2 환경 변수 (`.env`) 설정
운영 환경에서 사용할 서버 포트 및 로그인 암호를 설정합니다:
```bash
nano .env
```
아래 내용을 작성합니다:
```env
PORT=3000
NODE_ENV=production
DEFAULT_ADMIN_PASSWORD=원하는_관리자_비밀번호
DEFAULT_STAFF_PASSWORD=원하는_직원_비밀번호
```
*`Ctrl + O` -> `Enter` 키로 저장 후 `Ctrl + X`로 종료합니다.*

---

## 🔄 4. PM2 프로세스 관리자 기반 24시간 무중단 구동

서버 프로세스가 다운되거나 인스턴스가 재부팅되어도 자동으로 서비스가 복구되도록 PM2 프로세스 관리자를 설정합니다.

```bash
# 1. PM2 전역(Global) 설치
sudo npm install -g pm2

# 2. PM2로 웹 서버 시작 (ecosystem.config.js 활용)
pm2 start ecosystem.config.js --env production

# 3. 프로세스 상태 확인
pm2 status

# 4. 실시간 서버 로그 확인
pm2 logs shelflife-label-server

# 5. OS 재부팅 시 PM2 자동 실행 등록
sudo env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u ubuntu --hp /home/ubuntu
pm2 save
```

---

## 🌐 5. Nginx 리버스 프록시 설정 (80번 포트 연결)

웹 브라우저에서 포트 번호(`:3000`) 입력 없이 일반 HTTP(`http://<고정-IP>`)로 접속할 수 있도록 Nginx를 설정합니다.

### 5.1 Nginx 설치 및 설정 파일 작성
```bash
# 1. Nginx 설치
sudo apt install -y nginx

# 2. 웹 서버용 Nginx 설정 파일 생성
sudo nano /etc/nginx/sites-available/shelflife
```

아래 설정을 입력합니다:
```nginx
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

### 5.2 Nginx 설정 활성화 및 재시작
```bash
# 1. 기본 default 설정 제거 및 새 설정 심볼릭 링크 생성
sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -s /etc/nginx/sites-available/shelflife /etc/nginx/sites-enabled/

# 2. Nginx 문법 검사
sudo nginx -t

# 3. Nginx 서비스 재시작
sudo systemctl restart nginx
```

---

## 🔒 6. (선택 사항) HTTPS 무료 SSL 인증서 적용 (Certbot)

도메인(예: `label.yourdomain.com`)을 연결한 경우 무료 SSL 인증서를 발급받아 보안 접속(HTTPS)을 설정할 수 있습니다.

```bash
# 1. Certbot 설치
sudo apt install -y certbot python3-certbot-nginx

# 2. SSL 인증서 발급 및 Nginx 자동 구성 (도메인 DNS가 고정 IP로 연결되어 있어야 함)
sudo certbot --nginx -d yourdomain.com
```

---

## ✅ 7. 배포 검증 및 모니터링

### 7.1 접속 및 기능 확인
1. 웹 브라우저 주소창에 `http://<할당받은-고정-IP>` 접속을 확인합니다.
2. 관리자 아이디(`admin` / `.env`에서 설정한 비밀번호)로 로그인합니다.
3. 헬스 체크 API 응답 확인:
   `http://<할당받은-고정-IP>/api/health`

### 7.2 데이터 백업 및 유지관리
```bash
# SQLite 데이터베이스 수동 백업
cp ~/label/database.sqlite ~/label/database_backup_$(date +%Y%m%d).sqlite

# PM2 프로세스 현황 모니터링
pm2 status
```
