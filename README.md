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

## 2주 상품 크롤러

CU, GS25, 세븐일레븐, emart24의 공개 상품 목록은 크롤러로 수집합니다. GitHub Actions는 매일 Render API를 깨우지만, MongoDB에 저장된 마지막 성공 시각을 기준으로 실제 수집은 14일에 한 번만 실행됩니다. 일부 매장 수집이 실패하면 다음 날 다시 시도합니다.

자동 실행을 켜려면 같은 임의 문자열을 다음 두 곳에 `CRAWLER_REFRESH_SECRET`으로 설정합니다.

1. Render Dashboard의 `Environment`
2. GitHub 저장소의 `Settings -> Secrets and variables -> Actions -> New repository secret`

GitHub Actions의 `Refresh convenience products` 워크플로는 `Actions` 탭에서 수동 실행할 수도 있습니다. 실행 상태는 비밀키와 함께 `GET /api/internal/crawlers/convenience/status`로 확인할 수 있습니다.

현재는 크롤러 동작 확인을 위해 10분 간격 테스트 설정입니다. 테스트를 마치면 Actions 예약을 하루 한 번으로 되돌리고, Render의 `CRAWLER_REFRESH_INTERVAL_MINUTES`를 `20160`으로 변경해 2주 간격으로 운영합니다.
