# SHELFLIFE 라벨 프린터 시스템 (Express Server & Flutter Client)

SHELFLIFE 라벨 프린터 시스템은 매장 식자재 유통기한 관리 및 블루투스/네트워크 라벨 출력 기능을 제공하는 웹 서버 및 멀티플랫폼 Flutter 클라이언트입니다.

---

## 주요 기능 및 구조

- **Express/SQLite 백엔드 (`server.js`)**:
  - 인증 & 세션 관리: Scrypt 비밀번호 해싱, Rate Limiting, 관리자/스태프 권한 분리.
  - 마스터 데이터 관리: 카테고리, 보관 위치, 재료 및 유통기한, 라벨 규격.
  - API 동기화: ETag 기반 데이터 동기화 (`GET/POST /api/sync/database`).
  - 엑셀 업로드: 대용량 엑셀 파싱 및 트랜잭션 안전 원자적 업로드.
  - 출력 이력: 프린트 로그 저장 및 조회 (`GET/POST /api/print-logs`).
  - 헬스 체크: `GET /api/health` 시스템 및 DB 접속 모니터링.

- **Flutter 클라이언트 (`client_flutter`)**:
  - 서버 기반 세션 인증 (Fail-closed 오프라인 보안).
  - 라벨 프린터 출력 (블루투스 감열 프린터 및 PDF 출력 지원).
  - 테마 및 인터페이스: 다크/라이트 모드 지원.

---

## 시작하기 (Quickstart)

### 1. 백엔드 서버 실행
```bash
# 기본 의존성 설치
npm install

# 서버 실행 (개발 환경)
npm start

# 테스트 실행 (임시 테스트 DB에서 격리 수행)
npm test
```

### 2. Flutter 클라이언트 실행
```bash
cd client_flutter
flutter pub get
flutter run
```

---

## 문서 및 가이드

- [마이그레이션 및 백업 가이드](docs/MIGRATION_GUIDE.md)
- [운영 및 배포 가이드](docs/OPERATIONS.md)
- [PM2 설정](ecosystem.config.js)
- [환경 변수 템플릿](.env.example)
