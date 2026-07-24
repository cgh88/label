# SHELFLIFE 라벨 시스템 운영 및 배포 가이드

본 문서는 SHELFLIFE 서버 운영, PM2 프로세스 관리, Flutter 클라이언트 앱 빌드 및 비상 복구 절차를 안내합니다.

---

## 1. 서버 구동 및 프로세스 관리

### 1.1 기본 실행 (Node.js)
```bash
# 개발 모드 실행
npm start

# 테스트 실행 (독립된 임시 DB 사용)
npm test
```

### 1.2 PM2를 활용한 프로덕션 프로세스 관리
```bash
# PM2 설치 (글로벌)
npm install -g pm2

# 프로덕션 서버 시작
pm2 start ecosystem.config.js --env production

# 상태 확인
pm2 status

# 로그 실시간 모니터링
pm2 logs shelflife-label-server

# 프로세스 재시작
pm2 restart shelflife-label-server
```

---

## 2. Flutter 클라이언트 앱 빌드

### 2.1 Android APK 빌드
```bash
cd client_flutter

# 종속성 설치 및 코드 분석
flutter pub get
flutter analyze
flutter test

# 디버그 APK 빌드
flutter build apk --debug

# 릴리즈 APK 빌드
flutter build apk --release
```

---

## 3. 헬스 체크 및 모니터링

### 3.1 Health Check API
`GET /api/health`

응답 예시:
```json
{
  "status": "ok",
  "uptimeSeconds": 3600,
  "database": "connected",
  "timestamp": "2026-07-21T01:30:00.000Z",
  "version": "1.0.0"
}
```

---

## 4. 비상 롤백 및 장애 조치

### 4.1 백업 데이터베이스 복원
1. Node.js 서버 프로세스 중지 (`pm2 stop shelflife-label-server`).
2. 최근 백업된 `database.sqlite` 파일로 교체.
3. 서버 프로세스 재시작 (`pm2 start shelflife-label-server`).

### 4.2 시스템 마스터 데이터 초기화 API
관리자 웹 대시보드 또는 `POST /api/ingredients/reset` (Admin 권한 필요)을 통해 마스터 데이터를 기본 상태로 초기화할 수 있습니다.
