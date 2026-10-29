const fs = require('fs');
const path = require('path');

const pubspecPath = path.join(__dirname, '..', 'client_flutter', 'pubspec.yaml');
const appVersionDartPath = path.join(__dirname, '..', 'client_flutter', 'lib', 'config', 'app_version.dart');
const filesVersionJsonPath = path.join(__dirname, '..', 'files', 'app-version.json');

function getFormattedDate(date = new Date()) {
    const yyyy = date.getFullYear();
    const mm = String(date.getMonth() + 1).padStart(2, '0');
    const dd = String(date.getDate()).padStart(2, '0');
    const hh = String(date.getHours()).padStart(2, '0');
    const min = String(date.getMinutes()).padStart(2, '0');
    const ss = String(date.getSeconds()).padStart(2, '0');
    return `${yyyy}-${mm}-${dd} ${hh}:${min}:${ss}`;
}

function updateAppVersion() {
    if (!fs.existsSync(pubspecPath)) {
        console.error(`[오류] pubspec.yaml을 찾을 수 없습니다: ${pubspecPath}`);
        process.exit(1);
    }

    const content = fs.readFileSync(pubspecPath, 'utf8');
    const match = content.match(/^version:\s*([^\s+]+)(?:\+([0-9]+))?/m);

    if (!match) {
        console.error('[오류] pubspec.yaml에서 version 라인을 파싱할 수 없습니다.');
        process.exit(1);
    }

    const version = match[1];
    const buildNumber = match[2] ? parseInt(match[2], 10) : 1;
    const nowStr = getFormattedDate();
    const shortDate = nowStr.substring(0, 16);

    const dartDir = path.dirname(appVersionDartPath);
    if (!fs.existsSync(dartDir)) {
        fs.mkdirSync(dartDir, { recursive: true });
    }

    const dartContent = `// AUTO-GENERATED FILE. DO NOT MODIFY MANUALLY.
// Generated at: ${nowStr}

class AppVersion {
  static const String version = '${version}';
  static const int buildNumber = ${buildNumber};
  static const String buildDate = '${shortDate}';
  static const String fullBuildTimestamp = '${nowStr}';
  static const String display = 'v${version} (#${buildNumber} · ${shortDate})';
  static const String shortDisplay = 'v${version} (#${buildNumber})';
}
`;

    fs.writeFileSync(appVersionDartPath, dartContent, 'utf8');

    const filesDir = path.dirname(filesVersionJsonPath);
    if (fs.existsSync(filesDir)) {
        fs.writeFileSync(
            filesVersionJsonPath,
            JSON.stringify({ version, buildNumber: String(buildNumber), buildDate: nowStr }, null, 2) + '\n',
            'utf8'
        );
    }

    console.log(`[성공] 앱 버전 정보가 자동 생성되었습니다:`);
    console.log(` - 버전: v${version} (빌드 #${buildNumber})`);
    console.log(` - 빌드 일시: ${nowStr}`);
    console.log(` - 대상 파일: ${appVersionDartPath}`);
}

updateAppVersion();
