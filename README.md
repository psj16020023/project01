# PyeonPick

`Flutter + Node.js + MongoDB` 기반의 편의점 음식 추천 앱 프로젝트입니다.

## Deploy

이 저장소는 `Render`에서 바로 배포할 수 있도록 준비되어 있습니다.

1. GitHub 저장소를 Render에 연결합니다.
2. `New +` -> `Blueprint` 또는 `Web Service`를 선택합니다.
3. 이 저장소를 고릅니다.
4. 환경변수 `MONGO_URI`를 추가합니다.
5. 배포가 끝나면 같은 링크를 계속 사용할 수 있습니다.

배포 시 `Dockerfile` 안에서 Flutter 웹을 빌드하고, `backend/server.js`가 정적 웹과 API를 함께 제공합니다.
