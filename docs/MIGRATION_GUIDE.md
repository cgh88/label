# SHELFLIFE 라벨 시스템 마이그레이션 및 백업 가이드

본 문서는 SHELFLIFE Express/SQLite 서버와 Flutter 클라이언트의 데이터 마이그레이션 및 백업 절차를 설명합니다.

---

## 1. 데이터베이스 백업 절차

### 1.1 오프라인 라이브 백업 (추천)
SQLite 데이터베이스 백업은 SQLite CLI 또는 파일 복사 방식으로 손쉽게 수행할 수 있습니다.

```bash
# SQLite CLI 온라인 백업
sqlite3 database.sqlite ".backup 'backups/database_backup_$(date +%Y%m%m_%H%M%S).sqlite'"

# 파일 복사 백업 (서버 중지 권장)
cp database.sqlite backups/database_$(date +%Y%m%d).sqlite
```

---

## 2. 데이터베이스 스키마 마이그레이션

### 2.1 스키마 버전 감지 및 자동 마이그레이션
서버 시작 시 `initDatabaseAsync()` 함수가 실행되어 다음과 같이 스키마를 자동 검사하고 마이그레이션을 수행합니다:

1. 구버전 `ingredients` 테이블 존재 여부 확인 (`walkin` 컬럼 보유 여부).
2. 구버전 감지 시:
   - `categories` 및 `storage_locations` 기본 레코드 생성.
   - `ingredients_v2` 및 `ingredient_storage` 테이블로 데이터 이관.
3. 신규 설치 시:
   - 기본 카테고리 (해동, 워크인 랙산, 메이크라인, 소스보틀, 분할) 및 유통기한 데이터 시드.
   - 기본 라벨 프리셋 (50x30, 60x40, 70x40, 80x50, 100x60, 100x70) 생성.

---

## 3. 환경 변수 설정 및 보안 마이그레이션

### 3.1 프로덕션 환경 변수
프로덕션 실행 환경 (`NODE_ENV=production`)에서는 다음 환경 변수가 필수입니다:

```env
PORT=3000
NODE_ENV=production
DB_PATH=./database.sqlite
DEFAULT_ADMIN_PASSWORD=RequiredStrongAdminPassword!
DEFAULT_STAFF_PASSWORD=RequiredStrongStaffPassword!
SESSION_SECRET=Your32CharacterSecretRandomSessionKey!
```

### 3.2 사용자 비밀번호 마이그레이션 (SHA-256 -> Scrypt)
 legacy SHA-256 비밀번호는 사용자 첫 로그인 시 자동으로 솔트(Salt)가 적용된 Scrypt 해시로 투명하게 승격 저장됩니다.
