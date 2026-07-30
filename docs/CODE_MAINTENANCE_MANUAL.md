# 📘 소비기한 스마트 라벨 프린터 - 초보자용 소스코드 유지보수 매뉴얼

> **"중학생도 이해할 수 있는 친절하고 쉬운 코드 설명서!"**  
> 이 매뉴얼은 프로그램의 주요 파일과 코드가 어떻게 작동하는지 설명하고, 나중에 문구를 고치거나 기능을 수정할 때 어떤 파일을 수정해야 하는지 쉽게 안내합니다.

---

## 📂 1. 쉽게 보는 전체 파일 지도 (Project Map)

이 프로젝트는 **태블릿 전용 앱(Flutter/Dart)**과 **웹 화면 & 백엔드 서버(Node.js/JavaScript)**로 이루어져 있습니다.

```text
d:\DEV\aiCoding\label\
├── client_flutter/                      [안드로이드 태블릿 앱]
│   ├── lib/
│   │   ├── main.dart                    [1] 앱의 시작점 & 탭 메뉴 이동
│   │   ├── views/
│   │   │   ├── sauce_tab_view.dart      [2] 피자소스 관리 화면 (개봉, IN, OUT, 터치출력)
│   │   │   └── settings_tab_view.dart   [3] 블루투스 프린터 연결 & 설정 화면
│   │   └── services/
│   │       ├── bluetooth_service.dart   [4] 블루투스 프린터 명령어(TSPL) 및 인쇄 처리
│   │       ├── label_renderer.dart      [5] 라벨 스티커 디자인 및 여백 계산기
│   │       ├── database_service.dart    [6] 태블릿 내 저장소 (앱 꺼져도 데이터 보존)
│   │       └── api_sync_service.dart    [7] 서버와 데이터 주고받기 (통신)
│   └── pubspec.yaml                     [8] 앱 버전 및 외부 부품(패키지) 설정 파일
│
├── server.js                            [9] 웹 서버 & 데이터베이스(SQLite) 엔진
├── app.js                               [10] 웹 브라우저용 라벨 프로그램 로직
├── index.html                           [11] 웹 화면 레이아웃 (HTML)
└── style.css                            [12] 웹 화면 디자인 (CSS 색상, 글꼴)
```

---

## 📑 2. 주요 파일별 상세 역할 & 코드 설명

---

### [1] `client_flutter/lib/main.dart` (앱의 출발점)
- **역할**: 앱이 처음 켜질 때 실행되는 메인 파일입니다.
- **주요 기능**:
  - 앱의 테마(다크모드/라이트모드)를 관리합니다.
  - 상단 탭 메뉴(`등록 재료 인쇄`, `피자소스 관리`, `설정`) 이동을 관리합니다.
- **유지보수 조치 예시**:
  - 앱 첫 화면의 제목이나 기본 색상을 바꿀 때 수정합니다.

---

### [2] `client_flutter/lib/views/sauce_tab_view.dart` (핵심: 소스 관리 화면)
- **역할**: 소스통 ID 입력, PREP(최초개봉), IN(냉장입고), OUT(실온출고) 처리 및 미리보기/인쇄를 담당하는 **가장 핵심적인 파일**입니다.
- **주요 코드 위치 및 역할**:
  - `_triggerPrep()`: **[PREP (최초개봉)]** 버튼을 누르면 오늘 날짜 기반 식별번호(`S260730-001`)를 만들고 10시간 유효시간을 부여합니다.
  - `_triggerIn()`: **[IN (냉장보관)]** 버튼을 누르면 실온 차감 시간이 일시정지됩니다.
  - `_triggerOut()`: **[OUT (실온사용)]** 버튼을 누르면 냉장고에서 꺼내어 다시 실온 차감이 시작됩니다.
  - `_checkExpirations()`: **24시간 자동 정리 기능**. 생성된 지 24시간이 지난 소스는 태블릿과 서버에서 자동으로 삭제하여 앱을 쾌적하게 유지합니다.
  - `_formatDateTimeWithDay()`: 날짜를 **`26-07-30 (목) 14:00`** 형태로 2자리 년도와 요일을 붙여 예쁘게 변환합니다.
  - `_buildThermalLabelWidget()`: 화면 우측에 보이는 **초록색 라벨 미리보기 카드**를 그립니다. 터치하면 바로 출력이 시작됩니다.
  - `_printBluetoothLabel()`: 블루투스 프린터로 전송할 텍스트 데이터를 구성하고 출력을 요청합니다.

---

### [3] `client_flutter/lib/services/bluetooth_service.dart` (프린터 전송 통신)
- **역할**: 블루투스 라벨 프린터를 검색하고, 연결을 유지하며, 라벨 스티커를 TSPL 프린터 명령어 및 비트맵 이미지로 변환하여 출력합니다.
- **주요 코드 위치 및 역할**:
  - `autoConnect()`: 프린터 연결이 끊기면 이전에 연결했던 라벨 프린터를 자동으로 재연결합니다.
  - `printTsplLabel()`: 50x20mm 라벨 규격에 맞춰 글자 크기(`fontSize1~3`), 여백(`leftPaddingPercent: 5.0`)을 적용하여 출력 명령을 실행합니다.
  - `_executeTsplPrint()`: `[PREP]`, `[IN]`, `[OUT]` 라벨 텍스트에 중복 접두어가 붙지 않도록 검사한 후, TSPL 흑백 그림(Bitmap)으로 변환하여 프린터에 전송합니다.

---

### [4] `client_flutter/lib/services/label_renderer.dart` (라벨 그래픽 렌더러)
- **역할**: 화면에 보이는 미리보기 카드와 블루투스 프린터로 인쇄되는 결과물이 **100% 똑같은 픽셀 모양**을 갖도록 그리는 단일 그래픽 엔진입니다.
- **주요 코드 위치 및 역할**:
  - `paintLabel()`: 라벨의 좌우 여백(`rightPad = 6.0 * density`), 줄바꿈, 폰트 크기, 선명한 볼드(Bold) 효과를 계산하여 캔버스에 그립니다. 글자가 너무 길면 끝에 `…` 처리를 하거나 긴 글자를 자동으로 안전하게 줄여줍니다.

---

### [5] `server.js` (백엔드 서버 & 웹 다운로드 센터)
- **역할**: 데이터베이스(SQLite) 관리, 데이터 동기화 API, 안드로이드 APK 파일 다운로드 기능을 제공하는 서버 파일입니다.
- **주요 코드 위치 및 역할**:
  - `app.get('/api/app-info')`: 현재 빌드된 APK 파일의 버전(`v1.0.0`), 빌드번호, 빌드일시, 용량(`56.2MB`) 정보를 JSON으로 반환합니다.
  - `app.get('/download/app-release.apk')`: 웹 브라우저에서 태블릿용 APK 파일을 원클릭으로 다운로드할 수 있게 파일 스트림을 제공합니다.

---

### [6] `app.js` & `index.html` (웹 브라우저용 라벨 프로그램)
- **역할**: 태블릿 없이 컴퓨터 웹 브라우저에서도 소비기한 라벨링 시스템을 이용할 수 있도록 지원하는 웹 프로그램입니다.
- **주요 특징**:
  - `loadAppInfo()`: 웹 상단 헤더에 **[태블릿 APK 다운로드]** 배지를 만들어 빌드 정보를 실시간 표기합니다.
  - `checkSauceExpirations()`: 웹에서도 24시간 지난 데이터는 자동으로 정돈됩니다.

---

## 🛠️ 3. 초보자도 쉽게 따라하는 유지보수 Q&A (How-To)

### Q1. 라벨 스티커에 출력되는 문구를 변경하고 싶어요.
1. `client_flutter/lib/views/sauce_tab_view.dart` 파일을 엽니다.
2. `_printBluetoothLabel()` 함수(약 720번 줄)를 찾습니다.
3. 아래와 같이 표시하고 싶은 텍스트 문구를 수정합니다:
   ```dart
   // 예시: Prep: 을 개봉: 로 바꾸고 싶은 경우
   String prepDateStr = '개봉: ${_formatDateTimeWithDay(item.lastActionTime)}';
   ```

---

### Q2. 소스 ID가 24시간 후에 자동 삭제되는데, 시간을 48시간으로 바꾸고 싶어요.
1. `client_flutter/lib/views/sauce_tab_view.dart` 파일에서 `_checkExpirations()` 함수(약 74번 줄)를 엽니다.
2. 아래 줄에서 `Duration(hours: 24)` 숫자를 원하는 시간(예: `48`)으로 바꿉니다:
   ```dart
   final cutoff24h = now.subtract(const Duration(hours: 48)); // 48시간으로 변경
   ```

---

### Q3. 수정 후 태블릿에 새로 빌드해서 설치하고 싶어요.
VS Code 하단 터미널을 열고 아래 명령어를 순서대로 실행합니다:

```bash
# 1. client_flutter 폴더로 이동
cd client_flutter

# 2. 코드 에러 검사 (No issues found! 가 나오면 성공)
flutter analyze

# 3. 최신 APK 파일 빌드
flutter build apk --release

# 4. 태블릿으로 자동 설치 (ADB 연결 상태)
& "C:\Users\cho\AppData\Local\Android\Sdk\platform-tools\adb.exe" install -r "build\app\outputs\flutter-apk\app-release.apk"
```

---

### Q4. 수정한 소스코드를 깃허브(GitHub)에 저장(Push)하고 싶어요.
VS Code 터미널에서 아래 3줄을 입력하면 원격 저장소로 안전하게 저장됩니다:

```bash
git add .
git commit -m "수정한 내용 간단히 쓰기"
git push origin main
```

---

## 💡 유지보수 꿀팁 요약
- **화면 텍스트 수정**: `sauce_tab_view.dart`
- **프린터 인쇄 관련 수정**: `bluetooth_service.dart`
- **라벨 스티커 모양/여백 수정**: `label_renderer.dart`
- **웹 서버 및 APK 다운로드 수정**: `server.js`

작업 중 문의사항이나 기능 추가 요청이 필요하면 언제든 문의해주세요! 😊
