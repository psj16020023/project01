# pyeonpick_app

`편pick` Flutter 앱 프로젝트입니다.

이 앱은 기본적으로 `mock` 데이터 모드로 실행되므로, 백엔드 서버 없이도 바로 에뮬레이터나 데스크톱에서 확인할 수 있습니다.

## Run

프로젝트 폴더:

```bash
cd /Users/parksinjae/Documents/실적물/frontend/pyeonpick_app
```

기본 앱 실행:

```bash
../../flutter_sdk/bin/flutter run -d macos --dart-define=DATA_MODE=mock
```

웹 실행:

```bash
../../flutter_sdk/bin/flutter run -d chrome --dart-define=DATA_MODE=mock
```

## Remote API Mode

나중에 `Node.js + MongoDB` 서버에 붙여서 실행하려면 원격 모드로 실행하면 됩니다.

Android 에뮬레이터:

```bash
../../flutter_sdk/bin/flutter run -d android --dart-define=DATA_MODE=remote --dart-define=API_BASE_URL=http://10.0.2.2:3000/api
```

iOS 시뮬레이터:

```bash
../../flutter_sdk/bin/flutter run -d ios --dart-define=DATA_MODE=remote --dart-define=API_BASE_URL=http://127.0.0.1:3000/api
```

macOS:

```bash
../../flutter_sdk/bin/flutter run -d macos --dart-define=DATA_MODE=remote --dart-define=API_BASE_URL=http://127.0.0.1:3000/api
```

웹:

웹은 현재 접속 중인 주소 기준으로 같은 서버의 `/api`를 자동으로 사용합니다.

```bash
../../flutter_sdk/bin/flutter run -d chrome --dart-define=DATA_MODE=remote
```

배포용 웹 빌드:

```bash
../../flutter_sdk/bin/flutter build web --dart-define=DATA_MODE=remote --pwa-strategy=none
```

실제 안드로이드 폰에 설치할 APK:

설치형 앱은 웹처럼 현재 주소를 자동으로 따라가지 않으므로, 공개 터널 주소를 `API_BASE_URL`로 넣어 빌드해야 합니다.

```bash
cd /Users/parksinjae/Documents/실적물
npm run flutter:apk:public
```

## Current Local Tool Status

이 환경에서 확인된 상태:

- `flutter analyze` 통과
- `flutter test` 통과
- `flutter build web --dart-define=DATA_MODE=mock` 통과
- Android SDK 미설치
- Xcode 전체 설치 미완료
- CocoaPods 미설치
- 등록된 Android/iOS 에뮬레이터 없음

즉, 현재 이 코드 자체는 앱 프로젝트로 정리되어 있지만, 실제 Android 에뮬레이터/iOS 시뮬레이터 실행을 하려면 개발 도구 설치가 추가로 필요합니다.
