# 편pick 기술 설계·핵심 알고리즘·면접 준비서

> 기준 저장소: 현재 `PyeonPick` 프로젝트 코드  
> 기술 스택: Flutter(Dart) · Node.js/Express(JavaScript) · MongoDB/Mongoose · Render · GitHub Actions  
> 문서 목적: 기능 소개를 넘어, 입력부터 처리·저장·응답까지의 흐름과 설계 이유, 한계, 개선안을 코드 근거와 함께 설명한다.

---

## 초록

편pick은 편의점 상품과 사용자 조합 게시글을 연결하여 검색, 바코드 조회, 개인화 추천, 투표, 후기 작성 기능을 제공하는 풀스택 애플리케이션이다. Flutter가 웹·모바일 사용자 인터페이스를 담당하고, Express 서버가 REST API와 Flutter 웹 정적 파일을 함께 제공하며, MongoDB가 사용자·게시글·상품·투표·크롤러 상태를 문서 형태로 저장한다.

이 프로젝트에서 면접용으로 가장 가치 있는 기술적 주제는 다음 여섯 가지다.

1. 편봇의 규칙 기반 분석, OpenAI 상황 분석, 사용자 행동 신호를 결합한 하이브리드 추천
2. HACCP 공공데이터와 OpenFoodFacts를 결합하는 바코드 상품 식별 및 캐시 전략
3. 게시글 피드를 중복 없이 이어 읽는 생성 시각·문서 ID 기반 커서 페이지네이션
4. 중복 투표와 동시 수정 손실을 방지하는 픽쇼츠 원자적 갱신
5. CU·GS25·세븐일레븐·이마트24의 서로 다른 페이지를 수집하는 다중 크롤러와 14일 스케줄
6. bcrypt와 JWT를 이용한 인증 구조, 그리고 현재 코드에 남아 있는 권한·토큰 보관 문제

이 문서는 현재 코드를 과장하지 않는다. 잘 구현된 부분은 근거와 함께 설명하고, 불완전한 부분은 면접에서 숨기지 않고 개선 방향까지 말할 수 있도록 구분한다.

### 문서 범위 기준

이 문서는 로그인 후 사용자가 실제로 접근하는 꿀조합 공유, 게시글 상세·후기, 바코드 조회, 편봇, 픽쇼츠, 내 정보 흐름과 이를 직접 지원하는 서버 로직만 다룬다. 소스 파일에 흔적만 남아 있고 현재 사용자 흐름에서 호출되지 않는 실험 코드, 과거 화면용 위젯, 사용하지 않는 분류 로직은 프로젝트 기능으로 소개하지 않는다.

---

## 1. 프로젝트를 한 문장으로 설명하기

> 편pick은 사용자의 예산·맛 취향·현재 상황·좋아요·픽쇼츠 투표 기록을 조합 게시글과 연결하고, 바코드 및 편의점 공개 상품 데이터까지 통합하여 실제 선택을 돕는 Flutter 기반 편의점 음식 추천 서비스입니다.

### 30초 소개

편pick은 Flutter 프론트엔드와 Node.js·Express 백엔드, MongoDB로 구성했습니다. 사용자가 바코드를 찍으면 서버가 내부 크롤링 데이터와 캐시를 먼저 확인하고, 없으면 HACCP와 OpenFoodFacts를 조회합니다. 편봇은 예산을 먼저 엄격히 필터링한 뒤 취향, 상황, 좋아요, 픽쇼츠 투표 기록으로 점수를 계산합니다. 외부 AI가 실패해도 로컬 규칙으로 추천이 계속되도록 폴백을 두었습니다.

### 1분 소개

편pick의 핵심 문제는 편의점 음식 정보가 여러 출처에 흩어져 있고, 사용자가 단순 상품 목록보다 현재 예산과 기분에 맞는 실제 조합을 원한다는 점이었습니다. 그래서 Flutter 앱에서는 바코드·커뮤니티·추천·투표 UI를 제공하고, Express 서버에서는 인증, 게시글, 상품 통합, 추천 보조, 크롤링 API를 제공합니다. MongoDB에는 사용자, 게시글, 상품별 출처, 픽쇼츠 투표, 크롤러 실행 상태를 저장합니다. 추천은 생성형 AI에게 상품 선택을 전부 맡기지 않고, 코드가 예산 필터와 점수 계산을 담당한 뒤 AI는 상황 분석과 자연스러운 문장 표현만 보조하게 설계했습니다. 덕분에 예산을 넘거나 DB에 없는 상품을 지어내는 위험을 줄였습니다.

---

## 2. 전체 아키텍처

```text
[사용자]
   │
   ▼
[Flutter 웹/모바일]
   ├─ 화면 상태 및 낙관적 UI
   ├─ MobileScanner 바코드 인식
   ├─ SharedPreferences 세션 캐시
   └─ PostRepository 인터페이스
             │ HTTP/JSON + Bearer JWT
             ▼
[Node.js + Express API]
   ├─ 인증·사용자 API
   ├─ 게시글·후기·반응 API
   ├─ 편봇 분석·답변 API ───────► [OpenAI Responses API]
   ├─ 바코드 상품 통합 ─────────► [HACCP] [OpenFoodFacts]
   ├─ 편의점 상품 크롤러 ───────► [CU] [GS25] [7-Eleven] [emart24]
   └─ Flutter build/web 정적 제공
             │ Mongoose
             ▼
          [MongoDB]

[GitHub Actions] ── 보호된 API 호출 ──► [14일 주기 크롤러]
[Render Docker] ── Flutter 빌드 + Express 실행
```

### 현재 화면 기준 기능 대응표

| 실제 화면 | 사용자가 하는 동작 | 연결되는 핵심 코드 |
|---|---|---|
| 로그인·회원가입 | 아이디·닉네임·비밀번호로 계정 생성 및 로그인 | `AuthScreen`, `LocalAccountStore`, `/api/auth/*` |
| 꿀조합 공유 | 검색, 태그·가격 필터, 게시글 조회·등록·수정·삭제 | `CommunicationBody`, `ComposerPage`, `/api/posts` |
| 게시글 상세 | 좋아요·싫어요·보관, 댓글, 개별 후기 작성 | `PostDetailPage`, `PostReviewsScreen`, 게시글 하위 API |
| 바코드 | 카메라로 상품 코드를 읽어 상품명 조회 | `ProductScannerSheet`, `/api/products/lookup/:barcode` |
| 픽쇼츠 | 두 조합 비교 글 생성, 한 번 투표, 종료 결과 확인 | `CombinationBattleScreen`, `/api/battles/*` |
| 편봇 | 초기 취향 설정, 예산·상황 대화, 실제 게시글 추천 | `PyeonBotPage`, `BotBudgetRules`, `/api/bot/*` |
| 내 정보 | 초기 설정 펼치기·접기, 프로필과 활동 정보 관리 | `ProfilePage`, `/api/users/:id` |

이후의 알고리즘 설명은 위 화면으로 이어지는 코드만 선택한다. 예를 들어 크롤러는 독립 화면은 아니지만 바코드와 상품 정보의 입력 데이터를 만들기 때문에 포함하고, 호출되지 않는 과거 UI 코드는 제외한다.

### 요청의 실제 흐름

게시글 조회를 예로 들면 다음 순서로 실행된다.

1. Flutter의 `RemotePostRepository.fetchPosts()`가 검색 조건을 쿼리 파라미터로 만든다.
2. `GET /api/posts` 요청을 보낸다.
3. Express가 검색어, 태그, 가격, 성별 선호, 작성자 필터를 MongoDB 쿼리로 바꾼다.
4. 정렬 기준과 커서에 맞는 문서만 `limit + 1`개 조회한다.
5. 다음 페이지 존재 여부와 다음 커서를 계산한다.
6. Flutter가 JSON을 `PostPage`와 `Post` 정적 타입 객체로 변환한다.
7. 화면 상태를 갱신하고, 실패하면 한 번 재시도한 뒤 오류 안내를 표시한다.

### 한 서버에서 웹과 API를 함께 제공한 이유

`Dockerfile`은 첫 단계에서 Flutter 웹을 빌드하고, 두 번째 Node 이미지에 결과물을 복사한다. Express는 `/api` 요청을 처리하면서 그 외 경로에는 `index.html`을 보낸다. 따라서 웹에서는 현재 접속한 출처의 `/api`를 사용할 수 있고, 프론트와 API 도메인이 분리될 때 생기는 CORS·환경별 URL 문제를 줄인다.

---

## 3. 기술 스택과 언어 선택

| 영역 | 실제 기술 | 역할 |
|---|---|---|
| 프론트엔드 | Flutter, Dart | 웹·모바일 공통 UI와 정적 타입 모델 |
| 바코드 | `mobile_scanner` | EAN/UPC/ITF/Code128 카메라 인식 |
| 백엔드 | Node.js, Express 5, JavaScript | REST API, 외부 API, 크롤링, 정적 웹 제공 |
| 데이터베이스 | MongoDB, Mongoose | 문서 저장, 스키마 검증, 인덱스 |
| 인증 | bcryptjs, JWT | 비밀번호 해시, 로그인 토큰 |
| AI | OpenAI Responses API | 구조화된 상황 분석과 자연어 답변 보조 |
| 배포 | Docker, Render | 멀티스테이지 빌드와 단일 웹 서비스 |
| 자동 실행 | GitHub Actions | 매일 서버를 깨우고, DB 기준 14일 주기 검사 |
| 테스트 | Node test runner, Flutter test | 핵심 함수·API·위젯 검증 |

### JavaScript 동적 타입과 Dart 정적 타입

현재 백엔드는 TypeScript가 아니라 JavaScript다. JavaScript는 변수 타입을 실행 중 결정하므로 잘못된 값이 실제 경로를 실행할 때 발견될 수 있다. Mongoose 스키마와 수동 검증으로 일부 위험을 보완하지만 컴파일 단계의 타입 검사는 없다.

반면 Flutter의 Dart는 정적 타입 언어다. 예를 들어 `Future<PostPage>`를 반환해야 하는 함수가 문자열을 반환하면 실행 전에 분석기에서 오류를 발견한다. `Post.fromJson`과 같은 경계에서는 외부 JSON을 캐스팅하므로 런타임 검증도 여전히 필요하다.

면접에서는 다음처럼 정확히 말하는 것이 좋다.

> 백엔드는 JavaScript라서 개발 속도는 빨랐지만 API 입력의 타입 오류가 런타임까지 갈 수 있습니다. Mongoose 스키마와 `Number`, `String`, `Array.isArray` 검증으로 보완했고, 프론트는 Dart의 정적 타입을 사용해 모델 불일치를 분석 단계에서 많이 잡았습니다. 규모가 커진다면 백엔드를 TypeScript로 전환하고 요청 스키마 검증 도구를 추가하겠습니다.

---

## 4. MongoDB 데이터 모델

SQL 데이터베이스는 데이터를 테이블·행·열로 나누고 외래 키와 JOIN으로 관계를 표현한다. MongoDB 같은 NoSQL 문서 데이터베이스는 컬렉션 안에 JSON과 비슷한 문서를 저장하며, 한 문서에 배열과 하위 문서를 중첩할 수 있다. 편pick은 후기, 댓글, 취향 설정처럼 구조가 함께 조회되는 값을 게시글 또는 사용자 문서 안에 넣기 쉬워 MongoDB와 잘 맞는다.

### 실제 컬렉션

Mongoose는 다음 모델명을 일반적으로 복수형 컬렉션으로 저장한다.

| 모델 | 대표 필드 | 목적 |
|---|---|---|
| `User` | `username`, `passwordHash`, `botSetup`, `likedPostIds` | 계정, 취향, 세션 관련 사용자 상태 |
| `Post` | 작성자, 가격 범위, 카테고리, 댓글, 후기, 이미지 | 조합 공유 게시글 |
| `Product` | 바코드, 공식명, 출처별 정보, 검색 토큰 | 외부 API 통합 상품 캐시 |
| `ProductLookupMiss` | 바코드, 실패 횟수, 확인 출처, 오류 | 찾지 못한 상품 관찰 |
| `CuProduct` | CU 상품 ID, 이름, 가격, 신규/PB 여부 | CU 크롤링 스냅샷 |
| `ConvenienceProduct` | 매장, 상품명, 가격, 태그 | GS25·세븐일레븐·이마트24 상품 |
| `CrawlerSchedule` | 상태, 시작·완료·실패 시간, 결과 | Render 재시작과 무관한 스케줄 상태 |
| `BattleMatch` | 양쪽 후보, 종료 시각, 투표자 ID 배열 | 픽쇼츠 투표 |

### 문서 중첩을 사용한 예

`Post`는 댓글과 후기를 별도 컬렉션 대신 배열로 포함한다.

```js
const postSchema = new mongoose.Schema({
  authorId: { type: String, required: true },
  title: { type: String, default: "제목 없는 꿀조합" },
  priceMin: { type: Number, required: true },
  priceMax: { type: Number, required: true },
  categories: [{ type: String, required: true }],
  comments: { type: [commentSchema], default: [] },
  reviews: { type: [postReviewSchema], default: [] },
  details: { type: postDetailsSchema, default: () => ({}) },
}, { timestamps: true });
```

장점은 상세 화면에서 게시글과 댓글·후기를 한 번에 읽는다는 것이다. 단점은 댓글과 후기가 무한히 늘면 문서가 커지고, MongoDB 문서 크기 제한과 갱신 충돌을 고려해야 한다. 서비스가 커지면 `reviews`와 `comments`를 독립 컬렉션으로 분리하고 `postId` 인덱스를 두는 편이 낫다.

### 참조와 중첩을 혼합한 이유

- 댓글·후기는 게시글에 종속되고 함께 읽기 때문에 중첩했다.
- 사용자의 좋아요는 `User.likedPostIds`에 게시글 ID를 저장한다.
- 픽쇼츠는 여러 사용자가 동시에 투표하므로 독립 `BattleMatch` 컬렉션으로 분리했다.
- 외부 상품은 동일 바코드에 여러 출처가 있으므로 `Product.sources` 하위 문서 배열로 출처별 원본을 남긴다.

### 인덱스

상품 바코드는 `unique + index`, 사용자 아이디와 닉네임도 `unique + index`다. 상품명·별칭·브랜드에는 텍스트 인덱스가 있고, 편의점 상품에는 매장·정규화 이름 복합 인덱스가 있다. 인덱스는 읽기를 빠르게 하지만 저장·수정 시 인덱스도 갱신하므로 무조건 많이 추가하지 않는다.

---

## 5. Repository 패턴과 실행 환경 분리

Flutter 화면은 서버 구현을 직접 알지 않고 `PostRepository` 인터페이스에 의존한다.

```dart
abstract class PostRepository {
  Future<PostPage> fetchPosts({
    String? query,
    String? cursor,
    int? limit,
    required SortMode sortMode,
  });

  Future<Post> toggleLike(Post post, String currentUserId);
  Future<ProductLookupResult> lookupProductByBarcode(String barcode);
}

PostRepository createPostRepository(AppEnvironment environment) {
  return switch (environment.dataMode) {
    DataMode.remote => RemotePostRepository(baseUrl: environment.apiBaseUrl),
    DataMode.mock => MockPostRepository(),
  };
}
```

이 구조의 이점은 다음과 같다.

- UI 코드를 바꾸지 않고 실제 API와 Mock 데이터를 교체할 수 있다.
- 위젯 테스트가 외부 서버 없이 동작한다.
- 네트워크 직렬화와 화면 상태 변경의 책임이 분리된다.
- 실패 테스트나 데모 데이터를 만들기 쉽다.

`AppEnvironment`는 `String.fromEnvironment`로 빌드 시 값을 받는다. 웹은 기본적으로 `${Uri.base.origin}/api`, Android 에뮬레이터는 `10.0.2.2`, iOS·데스크톱은 `127.0.0.1`을 사용한다.

주의할 점은 Flutter의 `--dart-define` 값이 웹 번들에 포함된다는 것이다. 따라서 공개되어도 되는 API 주소나 지도용 공개 키만 넣어야 하며, `JWT_SECRET`, HACCP 서비스키, OpenAI 키 같은 서버 비밀값은 넣으면 안 된다.

---

## 6. 핵심 알고리즘 1: 편봇 하이브리드 추천

### 6.1 생성형 AI가 전부 추천하지 않는 이유

생성형 AI에게 “5천 원으로 추천해 줘”만 보내면 존재하지 않는 상품, 오래된 가격, DB에 없는 조합을 답할 수 있다. 편pick은 책임을 나눴다.

```text
사용자 문장
  ├─ 로컬 예산 규칙: 최대/최소/모호성 판단
  ├─ 로컬 감정·상황 규칙: 항상 가능한 폴백
  ├─ OpenAI 구조화 분석: 선택적 상황 보완
  ├─ DB 게시글 가격 필터: 절대 조건
  ├─ 코드의 추천 점수 계산: 후보 순위
  └─ OpenAI 답변 생성: 선택된 후보만 자연스럽게 표현
```

즉 AI는 후보를 마음대로 만들지 못하고, 실제 DB 후보 안에서 문장을 다듬는다. API 키가 없거나 시간 초과가 발생하면 로컬 분석과 로컬 초안이 그대로 사용된다.

### 6.2 한 턴의 실행 순서

`HomeScreen._sendBotPrompt()`의 핵심 흐름은 다음과 같다.

1. 사용자의 메시지를 먼저 로컬/서버 사용자 상태에 저장한다.
2. 오래된 화면 목록이 아니라 최신 전체 게시글 카탈로그를 다시 가져온다.
3. `/api/bot/analyze`로 문장을 분석한다.
4. 로컬 `_buildBotReply()`가 예산 필터와 추천 점수를 계산한다.
5. 선택된 게시글 ID만 `/api/bot/reply`에 넘긴다.
6. AI 문장이 성공하면 사용하고, 실패하면 로컬 초안을 사용한다.
7. 추천 ID, 해석된 예산, 문맥, 기억을 메시지와 함께 저장한다.

중간마다 `mounted`와 현재 사용자 ID를 다시 확인한다. 사용자가 화면을 닫거나 계정을 바꾼 뒤 늦게 도착한 비동기 응답이 다른 사용자 화면을 갱신하는 일을 막기 위한 것이다.

### 6.3 예산 문장 파싱과 상태 머신

한국어 가격 표현은 단순 정수만 오지 않는다. 현재 규칙은 `5천 원`, `1.5만 원`, `1만 5천 원`, `5000원`을 처리한다.

```dart
static int? _extractAmount(String prompt) {
  final compound = RegExp(r'(\d+)\s*만\s*(\d+)\s*천\s*원?')
      .firstMatch(prompt);
  if (compound != null) {
    return int.parse(compound.group(1)!) * 10000
         + int.parse(compound.group(2)!) * 1000;
  }

  final man = RegExp(r'(\d+(?:\.\d+)?)\s*만\s*원?').firstMatch(prompt);
  if (man != null) return (double.parse(man.group(1)!) * 10000).round();

  final thousand = RegExp(r'(\d+(?:\.\d+)?)\s*천\s*원?')
      .firstMatch(prompt);
  if (thousand != null) {
    return (double.parse(thousand.group(1)!) * 1000).round();
  }

  final won = RegExp(r'(\d{3,7})\s*원').firstMatch(prompt);
  return won == null ? null : int.tryParse(won.group(1)!);
}
```

`5000원 이상`은 “예산이 5000원 이상 있다”와 “5000원 이상 가격 상품”으로 해석될 수 있다. 그래서 즉시 가정하지 않고 `pendingClarification = budgetDirection`을 메시지에 저장한 뒤 다음 답변을 해석한다. 이것은 대화 상태 머신이다.

```text
일반 상태
  └─ "5000원 이상" 발견
       └─ 방향 확인 상태(pendingClarification)
            ├─ "최대 예산이야" → maximumBudget = 5000
            ├─ "비싼 거"      → minimumPrice = 5000
            └─ 불명확           → 한 번 더 질문
```

가격 허용 조건은 일부 가격만 맞는 것을 방지한다.

```dart
if (maximumBudget != null &&
    (priceMax <= 0 || priceMax > maximumBudget)) return false;
if (minimumPrice != null &&
    (priceMin <= 0 || priceMin < minimumPrice)) return false;
```

예를 들어 가격 범위가 4,500~6,000원인 게시글은 최대 예산 5,000원 추천에서 제외된다. 최저가만 보고 포함하면 실제 구매 비용이 예산을 넘을 수 있기 때문이다.

### 6.4 OpenAI 구조화 상황 분석

`POST /api/bot/analyze`는 JWT로 사용자 신원을 확인하고, OpenAI에 감정·예산·시간·야식 여부·원하는 맛을 JSON Schema로 요청한다. 자유 텍스트가 아니라 스키마를 강제하여 파싱 실패와 예상하지 못한 필드를 줄인다.

```js
text: {
  format: {
    type: "json_schema",
    name: "pyeonpick_situation",
    strict: true,
    schema: {
      type: "object",
      additionalProperties: false,
      properties: {
        emotion: { type: "string", enum: ["neutral", "happy", "tired", "sick"] },
        budget: { type: ["integer", "null"] },
        lateNight: { type: "boolean" },
        wantedTastes: {
          type: "array",
          items: { type: "string", enum: ["달달", "매콤", "새콤", "짭짤"] }
        }
      }
    }
  }
}
```

OpenAI 키가 없거나 응답이 비정상·시간 초과라면 `analyzeBotPromptLocally()` 결과를 반환한다. 외부 AI를 단일 실패 지점으로 만들지 않은 것이다.

### 6.5 픽쇼츠 투표를 취향 신호로 바꾸는 알고리즘

`buildVotePreferences()`는 인증된 사용자가 실제로 한 투표만 읽는다. 같은 매치가 중복 입력돼도 한 번만 계산하고, 양쪽 모두 또는 어느 쪽도 선택되지 않은 데이터는 버린다.

일반 투표에서는 선택한 쪽 카테고리에 `+1`을 준다. 현재 질문과 매치 제목이 같은 주제라면 선택 카테고리는 `+2`, 반대편 카테고리는 `-1`로 더 강하게 반영한다. 다만 미선택을 일반적인 “싫어요”로 단정하지 않는다.

```js
const topicMatch = sameTopic(match.title, prompt);
for (const category of chosen.categories) {
  counts.set(category, (counts.get(category) || 0) + (topicMatch ? 2 : 1));
}
if (topicMatch) {
  for (const category of rejected.categories) {
    counts.set(category, (counts.get(category) || 0) - 1);
  }
}
```

프론트의 점수 변환식은 다음과 같다.

```text
affinity = 후보 카테고리별 categoryWeight 합
신뢰도 = clamp(표본 수 / 5, 0, 1)
투표 보너스 = round(affinity × 3 × 신뢰도), 최종 0~6 제한
```

표본이 한 개라면 최대 영향이 작고, 다섯 개 이상 쌓였을 때 충분히 반영된다. 콜드 스타트에서 우연한 한 번의 투표가 추천 전체를 지배하지 않게 한 것이다.

### 6.6 최종 추천 점수

먼저 가격 조건에 맞는 게시글만 남긴 후 아래 점수를 더한다.

| 신호 | 현재 가중치 또는 규칙 |
|---|---|
| 픽쇼츠 취향 | 0~6점 |
| 목표 카테고리 일치 | 항목당 +5 |
| 문장의 상황 태그 일치 | 항목당 +6 |
| 좋아요 게시글과 카테고리 겹침 | 좋아요 게시글당 +2 |
| 사용자 1순위 가치 | +9 |
| 사용자 2순위 가치 | +6 |
| 맛 강도 차이 0/1/2/3 이상 | +4/+2/-3/-7 |
| 네 맛이 모두 차이 1 이하 | 추가 +12 |
| 다이어트·단백질·가벼운 식사 | 키워드별 보너스/패널티 |
| 연령별 한 끼 칼로리 범위 | 식사 요청 시 최대 +12, 초과 시 최대 -14 |

핵심 코드는 다음 구조다.

```dart
var score = votePreferences?.score(post.categories) ?? 0;

for (final category in targetCategories.map(_normalizeCategory)) {
  if (normalizedCategories.contains(category)) score += 5;
}

for (final liked in likedPosts) {
  if (liked.categories.map(_normalizeCategory)
      .any(normalizedCategories.contains)) score += 2;
}

for (final taste in ['달달', '매콤', '새콤', '짭짤']) {
  final difference =
      (setup.tasteLevel(taste) - (postTasteRatings[taste] ?? 3)).abs();
  score += switch (difference) {
    0 => 4,
    1 => 2,
    2 => -3,
    _ => -7,
  };
}
```

후기가 있으면 후기의 단맛·짠맛·매운맛·신맛 평균을 사용하고, 후기가 없으면 제목·내용·카테고리 키워드에서 휴리스틱 값 4 또는 2를 추정한다.

### 6.7 시간 복잡도

후보 수를 `N`, 사용자의 좋아요 게시글 수를 `L`, 맛 차원을 고정된 4개라고 하면 현재 정렬은 대략 `O(N × L + N log N)`이다. 좋아요 카테고리 집합을 미리 합쳐 두면 후보당 좋아요 순회를 제거하여 `O(N + N log N)`에 가깝게 개선할 수 있다.

### 6.8 환각 방지

서버는 AI 답변용 후보를 DB에서 다시 조회하고 최대 3개만 전달한다. 가격도 전체 범위를 재검증한다. 개발자 프롬프트에는 후보에 없는 상품명·가격·재고를 만들지 말라고 명시한다. 후보가 없으면 임의 추천 대신 조건을 다시 묻는다.

또한 대화 기록은 마지막 10개, 메시지당 1,500자로 제한하고 `user`와 `assistant` 역할만 허용한다. 사용자가 가짜 `developer` 역할을 넣는 프롬프트 인젝션을 줄이기 위한 경계다.

---

## 7. 핵심 알고리즘 2: 바코드 인식과 상품 데이터 통합

### 7.1 카메라에서 상품명까지

```text
MobileScanner
  → EAN/UPC/ITF/Code128 디코딩
  → 숫자만 남기기
  → 길이 8·12·13·14 확인
  → GET /api/products/lookup/:barcode
  → 크롤러 데이터 / Product 캐시 / 외부 제공자
  → ProductLookupResult
  → 검색창 또는 픽쇼츠 후보 제목·사진 자동 입력
```

Flutter는 카메라 이미지 자체를 서버에 보내지 않는다. 기기에서 바코드 문자열을 인식한 뒤 코드만 전송하므로 대역폭과 개인정보 노출을 줄인다.

```dart
String _retailBarcodeFromCapture(BarcodeCapture capture) {
  for (final barcode in capture.barcodes) {
    final raw = (barcode.rawValue ?? barcode.displayValue ?? '').trim();
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if ({8, 12, 13, 14}.contains(digits.length)) return digits;
  }
  return '';
}
```

### 7.2 조회 우선순위

서버의 현재 순서는 다음과 같다.

1. `CuProduct`에서 동일 바코드 검색
2. `ConvenienceProduct`에서 동일 바코드 검색
3. 이미 통합한 `Product` 캐시 검색
4. HACCP와 OpenFoodFacts를 병렬 요청
5. 성공한 후보를 병합하고 `Product`에 저장
6. 모두 실패하면 `ProductLookupMiss`에 실패 횟수·출처·오류 기록

내부 데이터와 캐시를 먼저 쓰므로 반복 스캔의 외부 API 비용과 응답 시간을 줄인다.

### 7.3 HACCP를 우선하는 병렬 병합

```js
const providers = [
  fetchProductFromHaccp,
  fetchProductFromOpenFoodFacts,
];

const candidates = await Promise.all(
  providers.map(async (provider) => {
    try { return await provider(barcode); }
    catch (error) {
      errors.push(`${provider.name}: ${error.message}`);
      return null;
    }
  })
);

const available = candidates.filter(Boolean);
const product = { ...available[0] };
```

`Promise.all`은 두 네트워크 요청을 동시에 실행하지만 결과 배열의 순서는 입력 배열과 같다. 따라서 두 출처가 모두 성공하면 첫 번째인 HACCP가 공식명과 주요 필드의 기준이 된다. OpenFoodFacts는 HACCP에 없는 칼로리, 매장, 이미지, 별칭, 카테고리를 보완한다.

### 7.4 HACCP 정확 일치 검증

HACCP 요청에 바코드를 넣어도 응답을 그대로 신뢰하지 않고 각 XML `<item>`의 바코드를 다시 정규화해 정확히 일치하는 항목만 선택한다.

```js
matchedItem = items.find((itemXml) => {
  const itemBarcode = extractXmlValue(itemXml, "barcode");
  return itemBarcode &&
    itemBarcode.replace(/[^0-9A-Za-z]/g, "") === normalizedBarcode;
}) || null;
```

API가 넓은 결과나 예상과 다른 상품을 반환했을 때 동일 바코드가 아닌 데이터를 막기 위한 검증이다.

### 7.5 출처 추적

통합 상품은 최종 필드만 저장하지 않고 `sources`에 출처별 이름, 가격, 칼로리, 확인 시각, 원본을 남긴다. 나중에 값이 충돌했을 때 “어느 출처에서 들어왔는가”를 확인할 수 있다.

### 7.6 실제 한계와 개선안

현재 캐시가 있으면 외부 제공자를 다시 조회하지 않는다. 과거에 잘못 저장된 이름이 있으면 HACCP 우선순위를 바꿔도 기존 캐시가 계속 반환될 수 있다. 또한 `mergeCandidateIntoProduct()`는 기존 `officialName`이 있으면 새 공식명으로 덮어쓰지 않는다.

개선 방법은 다음과 같다.

- `verificationStatus`에 출처 신뢰 등급을 숫자로 저장한다.
- 새 후보의 등급이 더 높으면 공식명을 교체한다.
- `lastVerifiedAt`이 일정 기간 지난 캐시는 백그라운드 재검증한다.
- 충돌 시 두 값을 관리자 검토 큐에 넣는다.
- GTIN 체크디지트 검증을 추가해 잘못 인식한 바코드를 요청 전에 거른다.

면접 답변 예시는 다음과 같다.

> 같은 바코드를 두 API가 다르게 반환한 경험이 있어, 단순히 먼저 도착한 응답을 쓰지 않고 공식 공공데이터인 HACCP를 우선하는 고정 순서를 만들었습니다. 두 요청은 병렬 실행해 속도를 유지하고, HACCP의 빈 필드만 OpenFoodFacts로 보완했습니다. 다만 이미 잘못 캐시된 상품은 자동 교정되지 않는 한계가 있어, 다음 단계로 출처 신뢰도와 캐시 재검증 정책을 추가하려 합니다.

---

## 8. 핵심 알고리즘 3: 게시글 피드 커서 페이지네이션

### offset 대신 cursor를 선택한 이유

`skip(1000)` 같은 offset 방식은 앞의 문서를 계속 건너뛰어야 하고, 사용자가 다음 페이지를 보는 사이 새 글이 생기면 중복·누락이 발생하기 쉽다. 편pick의 기본 피드는 마지막 게시글의 생성 시각과 문서 ID를 커서에 넣는다.

기본 정렬은 `(createdAt DESC, _id DESC)`다. 서버의 커서 함수 중 기본 피드 분기는 다음처럼 생성 시각이 더 오래됐거나, 생성 시각이 같을 때 `_id`가 더 작은 문서만 가져온다.

```js
return {
  $or: [
    { createdAt: { $lt: cursorDate } },
    { createdAt: cursorDate, _id: { $lt: cursorId } },
  ]
};
```

서로 다른 게시글의 생성 시각이 우연히 같아도 고유한 `_id`가 최종 tie-breaker가 되므로 순서가 결정된다.

서버는 `pageSize + 1`개를 읽는다. 초과 한 개가 있으면 `hasMore = true`로 판단하고 실제 응답에서는 제거한다. 별도 count 쿼리 없이 다음 페이지 존재 여부를 알 수 있다.

### 현재 한계

- 커서는 Base64 인코딩일 뿐 암호화나 서명이 아니다.
- 잘못된 `_id`를 넣은 커서의 오류 처리가 충분하지 않다.
- 커서 발급 이후 게시글의 생성 시각이 수정되는 예외 상황은 별도 정책이 필요하다.
- 기본 피드 정렬용 `{createdAt:-1, _id:-1}` 복합 인덱스를 명시하면 데이터 증가 시 더 안정적이다.

개선하려면 커서 payload를 HMAC 서명하고, Zod/Joi 같은 도구로 검증하며, `{createdAt:-1, _id:-1}` 복합 인덱스를 추가한다.

---

## 9. 핵심 알고리즘 4: 좋아요·싫어요의 낙관적 UI와 동기화

### 낙관적 UI

Flutter는 좋아요를 누르면 서버 응답을 기다리기 전에 화면 숫자와 상태를 바꾼다. 요청이 성공하면 서버값으로 확정하고, 실패하면 원래 `post`로 롤백한다. 같은 게시글에 중복 요청이 가지 않도록 `_reactionRequests` 집합도 사용한다.

```dart
if (_reactionRequests.contains(post.id)) return;
_reactionRequests.add(post.id);

final optimistic = post.copyWith(
  likedByMe: !post.likedByMe,
  dislikedByMe: false,
  likes: math.max(0, post.likes + (post.likedByMe ? -1 : 1)),
);
_applyUpdatedPost(optimistic);

try {
  final updated = await repository.toggleLike(post, currentUser.id);
  _applyUpdatedPost(updated);
} catch (_) {
  _applyUpdatedPost(post);
} finally {
  _reactionRequests.remove(post.id);
}
```

### 서버의 상호 배타 반응

좋아요를 추가할 때 기존 싫어요를 제거하고, 싫어요를 추가할 때 기존 좋아요를 제거한다. 숫자가 음수가 되지 않도록 `Math.max(0, value - 1)`을 적용한다.

### 일관성 한계

게시글과 사용자 문서를 `Promise.all([post.save(), user.save()])`로 저장하지만 MongoDB 트랜잭션은 사용하지 않는다. 하나만 성공하면 숫자와 사용자 ID 목록이 어긋날 수 있다. 또한 읽기-수정-저장 방식이라 동시에 같은 게시글에 반응하면 lost update 가능성이 있다.

개선안은 다음 중 하나다.

1. replica set 기반 MongoDB transaction으로 두 문서를 함께 커밋한다.
2. 반응을 별도 `Reaction(userId, postId, type)` 컬렉션에 unique 복합 인덱스로 저장한다.
3. `$inc`, `$addToSet`, `$pull` 조건부 갱신으로 원자성을 높인다.
4. 서버 응답을 반응 상태의 단일 기준으로 사용하고 클라이언트 캐시를 함께 갱신한다.

---

## 10. 핵심 알고리즘 5: 픽쇼츠 투표의 원자성

픽쇼츠는 두 조합 중 하나를 고르는 기능이다. 중요한 제약은 사용자당 한 번만 투표할 수 있고 종료 후에는 투표할 수 없다는 점이다.

```js
const match = await BattleMatch.findOneAndUpdate(
  {
    id: req.params.id,
    $and: [
      { leftVoterIds: { $ne: userId } },
      { rightVoterIds: { $ne: userId } },
      { $or: [{ endsAt: null }, { endsAt: { $gt: now } }] },
    ],
  },
  {
    $addToSet: side === "left"
      ? { leftVoterIds: userId }
      : { rightVoterIds: userId }
  },
  { returnDocument: "after" }
);
```

검사한 뒤 별도로 저장하는 것이 아니라 “아직 양쪽에 없고 종료 전인 문서”를 한 번의 조건부 갱신으로 바꾼다. 두 요청이 동시에 와도 먼저 성공한 요청 이후에는 조건이 맞지 않아 중복 투표가 막힌다. `$addToSet`도 배열 중복을 방지한다.

수정 API는 과거에 읽은 문서 전체를 `save()`하지 않고 편집 가능한 필드만 `$set`한다. 투표와 제목 수정이 동시에 일어나도 오래된 투표 배열로 덮어쓰지 않게 하기 위한 것이다.

종료 결과는 작성자 JWT의 `sub`로만 검색한다. 쿼리 파라미터의 `authorId`를 믿지 않으므로 다른 사용자가 작성자의 결과를 볼 수 없다. 확인한 결과 ID는 `battleResultReadIds`에 `$addToSet`으로 저장한다.

### 테스트로 증명한 동작

`backend/bot_api.integration.test.js`는 다음을 실제 in-memory MongoDB에서 확인한다.

- 같은 사용자의 두 번째 투표는 `accepted: false`
- 다른 사용자의 투표는 정상 합산
- 투표와 제목 수정이 동시에 실행되어도 두 투표가 유지
- 종료 전 결과는 비어 있음
- 종료 후 작성자만 결과를 봄
- 다른 사용자가 `authorId`를 위조해도 결과를 보지 못함
- 종료 후 투표는 HTTP 410

---

## 11. 핵심 알고리즘 6: 게시글 작성·후기 저장 흐름

현재 화면에서 사용자는 조합 공유 게시글을 만들고, 선택한 게시글의 상세 화면에서 후기와 댓글을 작성한다. 서버는 입력 JSON을 그대로 저장하지 않고 필수값과 숫자 범위를 정규화한다.

### 게시글 작성 순서

1. Flutter 작성 화면이 사진, 사용 상품, 가격 범위, 카테고리, 평점, 상세 설명을 `PostDraft`로 만든다.
2. `RemotePostRepository.createPost()`가 이미지 바이트를 Base64 문자열로 바꾸고 `POST /api/posts`에 전달한다.
3. 서버가 사진 존재 여부, 사용 상품 한 개 이상, 0보다 큰 평점을 검사한다.
4. 제목이 비어 있으면 사용 상품을 ` + `로 연결해 제목을 만든다.
5. 가격과 평점을 허용 범위로 정규화한 뒤 `Post` 문서를 생성한다.
6. Flutter가 목록과 편봇 추천용 게시글 풀을 다시 읽어 새 글을 반영한다.

```dart
body: jsonEncode({
  'authorId': draft.authorId,
  'authorNickname': draft.authorNickname,
  'title': draft.title,
  'content': draft.content,
  'priceMin': draft.priceMin,
  'priceMax': draft.priceMax,
  'categories': draft.categories,
  'imageDatas': draft.imageBytes.map(base64Encode).toList(),
  'imageUrls': draft.imageUrls,
  'details': draft.details.toJson(),
  'calories': draft.calories,
  'rating': draft.rating,
})
```

```js
if (!hasImage) {
  return res.status(400).json({ message: "사진은 꼭 필요합니다." });
}
if (normalizedDetails.usedProducts.length === 0) {
  return res.status(400).json({ message: "사용한 상품은 하나 이상 필요합니다." });
}
if (normalizedRating <= 0) {
  return res.status(400).json({ message: "평점은 꼭 필요합니다." });
}
```

### 후기 저장 순서

후기는 공용 입력칸이 아니라 개별 게시글 상세 화면에서 작성한다. 후기에는 글, 별점, 평가 태그, 단맛·짠맛·매운맛·신맛 1~5점, 주의사항이 들어간다. 서버는 별점과 맛 점수를 1~5 범위로 제한하고 허용된 태그만 저장한다. 저장된 맛 점수의 평균은 편봇이 해당 게시글의 맛 성향을 계산할 때 다시 사용한다.

```js
const review = {
  id: String(req.body.id || crypto.randomUUID()),
  authorId: String(req.body.authorId || ""),
  text: String(req.body.text || "").trim(),
  rating: Math.min(5, Math.max(1, Number(req.body.rating) || 3)),
  sweet: Math.min(5, Math.max(1, Number(req.body.sweet) || 1)),
  salty: Math.min(5, Math.max(1, Number(req.body.salty) || 1)),
  spicy: Math.min(5, Math.max(1, Number(req.body.spicy) || 1)),
  sour: Math.min(5, Math.max(1, Number(req.body.sour) || 1)),
};
post.reviews.push(review);
await post.save();
```

이 흐름의 핵심은 사용자 후기가 다시 편봇 추천 입력으로 연결된다는 점이다. 다만 현재 수정·삭제 권한이 body/query의 작성자 ID 문자열에 의존하므로 JWT의 `sub`로 작성자를 판별하도록 보완해야 한다.

---

## 12. 핵심 알고리즘 7: 다중 편의점 크롤러

### 매장별 전략

| 매장 | 방식 | 특징 |
|---|---|---|
| CU | 카테고리/PB AJAX HTML | 카테고리들은 병렬, 페이지는 순차 |
| GS25 | 세션·쿠키·CSRF 후 JSON 요청 | 이벤트·YouUs·Fresh Food 등 여러 소스 |
| 7-Eleven | 탭별 POST AJAX | 1+1, 2+1, PB 등 공개 상품 탭 순회 |
| emart24 | 공개 목록 HTML | PB·행사·FF 페이지 순회 |

모든 매장이 같은 형식이 아니므로 공통 크롤러 하나에 억지로 넣지 않고, 매장별 파서가 공통 상품 구조로 변환한다.

### 중복 제거 ID

편의점 상품 ID는 매장, 원본 상품 ID, 바코드, 정규화 이름, 출처 페이지를 연결해 SHA-1 일부로 만든다.

```js
function createConvenienceProductId(store, productId, barcode, name, sourcePage) {
  const seed = [store, productId || "", barcode || "",
    normalizeName(name), sourcePage].join("|");
  return `${store.toLowerCase()}-${crypto.createHash("sha1")
    .update(seed).digest("hex").slice(0, 16)}`;
}
```

여러 페이지에서 같은 상품이 나오면 `store|barcode 또는 productId 또는 normalizedName` 키로 병합하고 신규·PB·태그는 합집합으로 유지한다.

### 병렬성과 속도 제한의 균형

CU 카테고리들은 `Promise.all`로 병렬 수집한다. 반면 서로 다른 편의점 전체 크롤러는 공개 사이트의 rate limit를 피하기 위해 순차 실행한다. 네트워크 I/O에서 무조건 병렬화하는 것이 아니라 상대 서버 특성에 맞춘 선택이다.

### 14일 스케줄

GitHub Actions는 매일 API를 호출하지만 서버는 MongoDB의 `CrawlerSchedule.lastCompletedAt`을 확인한다. 실제 실행 간격은 Render 프로세스 메모리가 아니라 DB에 저장되므로 서버가 재시작하거나 sleep 상태였다가 깨어나도 유지된다.

```text
성공              → idle, 14일 뒤 실행
일부 매장 실패    → partial-failure, 전체 시도로 기록, 14일 뒤 실행
작업 자체 중단    → failed, 다음 날 재시도 가능
이미 실행 중      → already-running 반환
```

프로세스 내부 `activeAllConvenienceCrawl` Promise는 같은 인스턴스에서 중복 실행을 막는다. 실행 API는 `X-Crawler-Secret`을 요구하고, 비밀값 비교에는 `crypto.timingSafeEqual`을 사용한다.

### 분산 환경 한계

메모리 락은 Render 인스턴스가 여러 개면 전역 락이 아니다. 두 인스턴스가 동시에 시작할 가능성을 완전히 막으려면 MongoDB에서 `status != running` 조건의 `findOneAndUpdate`로 락을 획득하고 lease 만료 시간을 저장해야 한다.

---

## 13. 인증·인가·비밀번호

### 서버 비밀번호 저장

회원가입 시 비밀번호는 bcrypt cost 12로 해시한 뒤 `passwordHash`에 저장한다.

```js
function hashPassword(password) {
  return bcrypt.hashSync(String(password), 12);
}
```

bcrypt는 salt를 포함하며 느리게 설계되어 유출 시 무차별 대입 비용을 높인다. 로그인에서는 `bcrypt.compareSync`로 비교한다. 과거 SHA-256 해시는 로그인 성공 시 bcrypt로 자동 마이그레이션한다.

비밀번호는 `render.yaml`에 저장하지 않는다. `render.yaml`에는 서버 비밀값의 환경변수 이름만 선언할 수 있고, 실제 값은 Render Dashboard에서 넣는다. MongoDB에는 비밀번호 원문이 아니라 bcrypt 해시가 들어간다.

### JWT

로그인 성공 시 다음 내용으로 30일 JWT를 만든다.

```js
jwt.sign(
  { sub: user._id.toString(), username: user.username },
  JWT_SECRET,
  { expiresIn: "30d", issuer: "pyeonpick-api" }
);
```

보호 API는 `Authorization: Bearer <token>`을 읽고 서명과 issuer를 검증한다. `requireSelf`는 토큰의 `sub`와 URL의 사용자 ID가 같은지 확인한다. 운영 환경에서 `JWT_SECRET`이 없으면 서버 시작 자체를 실패시킨다.

### 현재 반드시 알아야 할 보안 문제

#### 1. 클라이언트 평문 비밀번호 캐시

원격 로그인 후 Flutter 코드는 서버 사용자 객체에 입력 비밀번호를 다시 넣고 `SharedPreferences`에 캐시한다.

```dart
final user = PyeonUser.fromJson(json['user']).copyWith(password: password);
await _cacheCurrentUser(user);
```

웹에서 SharedPreferences는 보통 localStorage 계열이므로 XSS나 기기 접근 시 원문 비밀번호가 노출될 수 있다. 서버의 bcrypt 저장이 안전해도 클라이언트 캐시 때문에 전체 시스템이 안전하다고 말하면 안 된다.

개선은 `PyeonUser.password` 필드를 원격 모드에서 완전히 제거하고, 계정 삭제 때만 사용자가 비밀번호를 다시 입력하게 하는 것이다.

#### 2. 토큰 저장 위치

JWT도 SharedPreferences에 저장한다. 웹에서는 JavaScript가 접근할 수 있어 XSS에 취약하다. 웹에서는 `Secure`, `HttpOnly`, `SameSite` 쿠키와 CSRF 대책을 함께 사용하는 방법을 검토하고, 모바일에서는 secure storage를 사용하는 것이 낫다.

#### 3. 게시글 API의 신원 위조 가능성

픽쇼츠와 사용자 API는 JWT로 보호하지만 게시글 생성·수정·삭제·좋아요·후기 일부는 JWT 없이 body/query의 `authorId` 또는 `userId`를 믿는다. 공격자가 다른 사용자 ID를 알면 요청을 위조할 수 있다.

개선 예시는 다음과 같다.

```js
app.put('/api/posts/:id', requireAuth, async (req, res) => {
  const post = await Post.findById(req.params.id);
  if (!post) return res.sendStatus(404);
  if (post.authorId !== req.auth.sub) return res.sendStatus(403);
  // 허용 필드만 수정
});
```

클라이언트가 보낸 `authorNickname`도 신뢰하지 말고 `req.auth.sub`로 DB 사용자 정보를 읽어야 한다.

#### 4. 이미지 프록시 SSRF

현재 이미지 프록시는 `http://`와 `https://`면 요청한다. `localhost`, 사설 IP, 클라우드 메타데이터 주소를 막지 않아 SSRF 위험이 있다. DNS 해석 후 private/link-local 범위를 거부하고 허용 도메인 목록, 최대 응답 크기, 리다이렉트 제한을 추가해야 한다.

#### 5. CORS와 입력 검증

현재 `cors()`는 넓게 열려 있고 많은 입력이 수동 변환에 의존한다. 운영 출처 allowlist와 공통 요청 스키마 검증, rate limit, 로그인 시도 제한을 추가하는 것이 좋다.

---

## 14. 이미지 저장과 이미지 프록시

게시글 작성 시 Flutter는 로컬 이미지 바이트를 Base64로 JSON에 넣는다. 서버는 최대 15MB JSON을 받고 `imageDatas` 배열에 저장한다. 조회 카탈로그에서는 Base64 전체를 되돌리지 않고 `/api/posts/:id/images/:index` URL을 만들어 전송량을 줄인다.

장점은 별도 스토리지 없이 구현이 단순하다는 것이다. 단점은 Base64가 원본보다 약 33% 커지고 MongoDB 문서와 백업 크기가 증가한다는 것이다. 운영 규모에서는 S3·Cloudinary 같은 객체 스토리지에 업로드하고 MongoDB에는 URL과 메타데이터만 저장해야 한다.

외부 상품 이미지는 Flutter 웹의 CanvasKit/CORS·AVIF 호환 문제를 피하기 위해 `/api/image-proxy`를 거친다. 프록시는 이미지 MIME인지 확인하고 Flutter가 처리할 수 있는 형식을 요청하며 성공 응답은 하루 캐시한다.

---

## 15. REST API 설계

### HTTP 메서드 의미

- `GET`은 데이터를 조회하며 서버 상태를 바꾸지 않는 요청에 사용한다.
- `POST`는 새 리소스를 만들거나 투표·좋아요 같은 명령을 실행할 때 사용한다.
- `PUT`은 알려진 리소스의 내용을 수정하는 데 사용한다.
- `PATCH`는 일부 필드만 부분 수정할 때 더 정확한 의미를 가진다.
- `DELETE`는 리소스를 삭제할 때 사용한다.

편pick 게시글은 조회 `GET /posts`, 등록 `POST /posts`, 수정 `PUT /posts/:id`, 삭제 `DELETE /posts/:id`로 연결된다. 현재 수정은 실제로 허용 필드만 갱신하므로 API 의미를 더 엄밀히 하려면 `PATCH`도 적합하다.

POST가 GET보다 무조건 안전한 것은 아니다. POST body도 HTTP에서는 평문으로 이동할 수 있고 개발자 도구·서버 로그·악성 스크립트에서 볼 수 있다. HTTPS는 전송 중 내용을 암호화하고 서버 인증서로 위조 서버 접속 위험을 줄인다. 다만 HTTPS도 서버·브라우저 저장소에 이미 저장된 평문이나 XSS까지 해결하지는 않는다.

### 주요 API 표

| 기능 | 메서드와 경로 | 인증 | 핵심 처리 |
|---|---|---|---|
| 회원가입 | `POST /api/auth/signup` | 없음 | bcrypt 해시, JWT 발급 |
| 로그인 | `POST /api/auth/signin` | 없음 | bcrypt 비교, JWT 발급 |
| 내 정보 조회·수정·삭제 | `GET/PUT/DELETE /api/users/:id` | JWT + 본인 | 토큰 `sub` 검사 |
| 편봇 분석 | `POST /api/bot/analyze` | JWT | AI/로컬 상황 분석, 투표 취향 |
| 편봇 문장 | `POST /api/bot/reply` | JWT | DB 후보만 사용한 답변 |
| 게시글 목록 | `GET /api/posts` | 없음 | 필터·정렬·커서 |
| 게시글 카탈로그 | `GET /api/posts/catalog` | 없음 | 추천용 최대 1000개 |
| 게시글 등록 | `POST /api/posts` | 현재 없음 | 사진·상품·평점 검증 |
| 반응 | `POST /api/posts/:id/like` | 현재 없음 | 좋아요/싫어요 상호 배타 |
| 후기 | `POST/PUT/DELETE .../reviews` | 현재 없음 | 작성자 ID 문자열 비교 |
| 픽쇼츠 | `/api/battles...` | JWT | 생성·투표·수정·결과 |
| 바코드 조회 | `GET /api/products/lookup/:barcode` | 없음 | 캐시 + 외부 API |
| 이미지 프록시 | `GET /api/image-proxy` | 없음 | 외부 이미지 전달 |
| 크롤러 실행 | `POST /api/internal/crawlers/.../run` | crawler secret | 14일 주기 실행 |
| 버전 | `GET /api/version` | 없음 | Render Git commit 확인 |

---

## 16. 비동기 처리·로딩·오류 복구

### 앱 시작

`PyeonPickApp`은 저장소와 세션을 비동기로 로드하는 동안 Splash 화면을 표시한다. 저장소를 열지 못하면 최대 세 번 재시도하고, 브라우저 저장소가 불가능하면 실행 중 메모리 저장소로 폴백하면서 경고를 보여준다.

### 게시글 로딩

게시글 로드는 첫 실패 후 350ms 기다렸다가 한 번 재시도한다. 계속 실패하면 원격 서버 주소나 상태를 확인하라는 오류 문구를 보여준다. 추가 페이지 로딩 중에는 `_loadingMore`로 중복 요청을 막는다.

### 선택 기능의 격리

추천용 전체 게시글 카탈로그처럼 선택적인 보조 요청이 실패해도 커뮤니티 전체를 막지 않는다. 이미 불러온 게시글을 폴백 풀로 사용한다.

### 타임아웃

- 일반 게시글 조회: 12초
- 좋아요/싫어요: 8초
- 편봇 분석: 15초
- 편봇 답변: 22초
- HACCP: 8초
- OpenFoodFacts: 7초
- 이미지 프록시: 8초

타임아웃은 무한 로딩을 막지만 요청 취소 후 서버 작업까지 반드시 중단되는 것은 아니다. 필요하면 클라이언트 요청 취소와 idempotency key를 추가할 수 있다.

---

## 17. 테스트 전략

### 백엔드 단위 테스트

`backend/bot_dialogue.test.js`는 다음을 검증한다.

- 인증 사용자 투표만 취향에 반영
- 중복 매치는 한 번만 계산
- 같은 주제의 선택 항목이 미선택 항목보다 높은 점수
- 최대·최소 가격이 전체 가격 범위를 만족
- 대화 기록은 마지막 10개, 각 1,500자
- 외부에서 전달한 developer 역할 제거
- 후보가 없을 때 임의 상품 추천 금지 프롬프트 유지

`backend/image_proxy.test.js`는 허용 Accept 형식, 정상 바이트 전달, 잘못된 URL, HTML 응답, timeout 오류를 검증한다.

### 백엔드 통합 테스트

`backend/bot_api.integration.test.js`는 실제 서버를 임시 포트에서 실행하고 in-memory MongoDB를 사용한다. 운영 DB와 OpenAI 키는 명시적으로 빈 값으로 덮어쓴다.

```js
env: {
  ...process.env,
  MONGO_URI: '',
  OPENAI_API_KEY: '',
  ALLOW_IN_MEMORY_MONGO: 'true',
  NODE_ENV: 'test',
  JWT_SECRET: 'local-integration-test-only',
}
```

이는 테스트가 실수로 운영 데이터를 삭제하거나 외부 API 비용을 쓰는 일을 막는다.

### Flutter 테스트

- 예산 문장과 모호성 처리
- 연령별 한 끼 칼로리 범위
- 로컬 계정 저장·로그인·삭제
- 픽쇼츠 투표 후 1초 결과 표시와 다음 카드 이동
- 희소 투표의 추천 영향 제한
- 모델 직렬화, 환경 URL, 이미지 URL, 테마, 인증 화면

### 추가해야 할 테스트

1. 게시글 API 전체를 JWT로 바꾼 후 타인 수정·삭제 403 테스트
2. 바코드 제공자 충돌 시 HACCP 우선 테스트
3. 캐시 만료와 재검증 테스트
4. 커서 경계값, 변조 커서, 정렬 중 반응 변경 테스트
5. 동시 좋아요의 lost update 테스트
6. 이미지 프록시 사설 IP·리다이렉트·대용량 응답 차단 테스트
7. 크롤러 lease 락과 부분 실패 상태 테스트

---

## 18. 환경변수와 배포

### 로컬

서버는 `backend/.env`를 읽는다. 예시는 다음과 같지만 실제 값은 Git에 커밋하지 않는다.

```dotenv
MONGO_URI=mongodb+srv://...
JWT_SECRET=충분히_긴_랜덤값
HACCP_SERVICE_KEY=발급받은_키
OPENAI_API_KEY=발급받은_키
CRAWLER_REFRESH_SECRET=별도_랜덤값
```

코드에서는 `process.env.HACCP_SERVICE_KEY`처럼 읽는다. Flutter의 공개 빌드 설정은 `--dart-define`으로 읽지만 서버 비밀키에는 사용하지 않는다.

### Render

Render Dashboard의 Environment에 실제 값을 저장한다. `render.yaml`의 `sync: false`는 값이 저장소에 들어가지 않고 배포 환경에서 별도로 설정되어야 함을 뜻한다. 현재 Blueprint에는 `MONGO_URI`, `JWT_SECRET`, `OPENAI_API_KEY`, `CRAWLER_REFRESH_SECRET`가 선언되어 있다. HACCP 키도 Dashboard에서 직접 설정할 수 있으며, 설정을 코드화하려면 `sync: false` 항목으로 이름만 추가한다.

### GitHub Actions

크롤러 호출용 `CRAWLER_REFRESH_SECRET`은 GitHub Repository Secret에 별도로 저장한다. Actions 로그에 값이 출력되지 않도록 환경변수로 전달하고 헤더에 사용한다.

### Docker 멀티스테이지

1. Flutter 이미지에서 `flutter pub get`
2. release web build 생성
3. Node 20 slim 이미지에서 production dependency 설치
4. 백엔드와 Flutter 산출물만 복사
5. `node backend/server.js` 실행

빌드 도구 전체를 런타임 이미지에 넣지 않아 이미지 크기와 공격 표면을 줄인다. `/api/version`은 `RENDER_GIT_COMMIT`을 반환하므로 배포한 커밋을 확인할 수 있다.

### 중요한 정정

비밀키를 GitHub 메인 브랜치에 푸시한 뒤 MongoDB와 연결하는 방식은 안전하지 않다. 키가 한 번 커밋되면 파일을 지워도 Git 기록에 남을 수 있다. 이미 푸시했다면 해당 키를 즉시 폐기·재발급하고 Git 기록 제거를 검토해야 한다. MongoDB에는 API 키가 아니라 API에서 가져온 상품 데이터를 저장한다.

---

## 19. 현재 구현의 좋은 설계와 기술 부채

### 좋은 설계

- AI가 아닌 코드가 가격 필터와 후보 선택을 최종 통제한다.
- 외부 AI 실패 시 로컬 분석과 답변으로 폴백한다.
- 픽쇼츠 투표는 조건부 원자 갱신으로 중복을 막는다.
- 투표 배열과 편집 필드를 분리해 동시 수정 손실을 줄였다.
- 페이지네이션에 고유 ID tie-breaker가 있다.
- 외부 상품 출처를 배열로 보존해 추적할 수 있다.
- 크롤러 스케줄을 DB에 저장해 프로세스 재시작에 견딘다.
- remote/mock repository를 분리해 테스트 가능성을 높였다.
- 운영 테스트에서 MongoDB와 OpenAI 환경변수를 비워 실제 서비스 접근을 막는다.

### 우선순위가 높은 기술 부채

| 우선순위 | 문제 | 영향 | 개선 |
|---|---|---|---|
| P0 | 원격 비밀번호가 클라이언트 캐시에 평문 저장 | 계정 탈취 | password 필드·병합 로직 제거 |
| P0 | 게시글·반응·후기 API 일부 무인증 | 타인 행위 위조 | 전 API JWT, `req.auth.sub` 사용 |
| P0 | 이미지 프록시 SSRF | 내부망 접근 | IP/도메인 검증, 크기·redirect 제한 |
| P1 | 좋아요가 두 문서 비트랜잭션 저장 | 데이터 불일치 | Reaction 컬렉션 또는 transaction |
| P1 | 이미지 Base64를 MongoDB에 저장 | 문서·전송량 증가 | Object Storage 사용 |
| P1 | 추천이 최대 1000개 카탈로그 | 데이터 증가 시 누락 | 서버 추천 쿼리/후보 검색 API |
| P2 | 거대한 `home_screen.dart` | 유지보수 어려움 | feature별 widget/controller 분리 |
| P2 | JS 입력 타입 수동 검증 | 런타임 오류 | TypeScript + Zod/Joi |
| P2 | 메모리 기반 크롤러 락 | 다중 인스턴스 중복 | DB lease lock |

---

## 20. 개선된 목표 아키텍처

```text
Flutter UI
  ├─ Auth feature
  ├─ Community feature
  ├─ Bot feature
  ├─ Battle feature
  └─ Scanner feature
         │
         ▼
Typed API client
         │ HTTPS + secure session
         ▼
TypeScript API
  ├─ request schema validation
  ├─ service layer
  ├─ repository layer
  └─ centralized error handling
         │
  ┌──────┴────────┐
  ▼               ▼
MongoDB       Object Storage
  │
  ├─ users
  ├─ posts
  ├─ reviews/comments
  ├─ reactions(unique userId+postId)
  ├─ products + source confidence
  └─ crawler leases
```

추천은 서버로 옮겨 동일한 알고리즘 버전을 모든 클라이언트가 사용하게 하고, 후보 검색은 MongoDB 필터와 인덱스로 줄인 뒤 점수 계산만 수행한다. 추천 결과에는 각 점수의 이유를 함께 저장해 설명 가능성과 A/B 테스트를 확보한다.

---

## 21. 면접 질문과 모범 답변

### Q1. 가장 어려웠던 기능은 무엇인가요?

편봇 추천이 가장 어려웠습니다. 자연어 요청에는 예산, 감정, 맛, 시간 같은 조건이 섞여 있고 AI에게 전부 맡기면 없는 상품을 만들 수 있었습니다. 그래서 예산은 정규식과 상태 머신으로 해석하고, DB 게시글을 가격으로 먼저 필터링한 뒤 취향·좋아요·투표·상황 점수를 계산했습니다. AI는 구조화 상황 분석과 최종 문장 표현만 담당하게 했고, 실패 시 로컬 규칙으로 폴백했습니다.

### Q2. 추천 알고리즘을 수식으로 설명해 보세요.

먼저 후보 `p`가 최대 예산이면 `p.priceMax <= budget`, 최소 가격 조건이면 `p.priceMin >= minimum`을 만족해야 합니다. 통과한 후보에 대해 투표 취향, 목표 카테고리, 상황 태그, 좋아요 유사성, 우선 가치, 네 가지 맛 거리, 건강 목적, 칼로리 범위 점수를 합산합니다. 최종 상위 3개를 추천합니다. 투표 신호는 표본 수가 5개가 되기 전까지 선형으로 감쇠하고 0~6점으로 제한해 콜드 스타트 과적합을 막았습니다.

### Q3. AI가 잘못된 상품을 추천하지 않게 어떻게 했나요?

AI에게 전체 상품 DB를 고르게 하지 않았습니다. 코드가 실제 게시글에서 최대 3개 ID를 선택하고, 서버가 ID를 다시 조회해 가격 조건을 검증한 뒤 후보 데이터만 AI에 전달합니다. 프롬프트도 후보에 없는 상품·가격·재고를 생성하지 못하게 했고 후보가 없으면 추천 대신 조건을 묻게 했습니다. API 실패 시에는 코드가 만든 초안을 보여줍니다.

### Q4. 두 상품 API가 같은 바코드를 다르게 답하면 어떻게 하나요?

두 요청은 병렬로 보내 응답 시간을 줄이되 결과 순서는 HACCP, OpenFoodFacts로 고정했습니다. HACCP 응답 안에서도 바코드 정확 일치를 재검증합니다. 공식명은 HACCP를 기준으로 하고 비어 있는 이미지·칼로리·카테고리는 OpenFoodFacts로 보완합니다. 각 출처 원본은 `sources`에 남깁니다. 다만 기존 오염 캐시 자동 교정은 아직 한계라 출처 신뢰도 기반 갱신이 다음 개선점입니다.

### Q5. 커서 페이지네이션이 왜 필요한가요?

offset은 앞의 데이터 변화로 중복·누락이 생기고 큰 offset일수록 비효율적입니다. 기본 피드에서는 마지막 항목의 생성 시각과 `_id`를 커서로 저장하고 그보다 뒤인 문서만 조회합니다. `_id`를 최종 tie-breaker로 사용해 생성 시각이 같은 게시글도 안정적인 순서를 만듭니다.

### Q6. 동시성 문제를 해결한 사례가 있나요?

픽쇼츠 투표에서 “투표 여부 조회 후 저장”을 하면 동시에 두 요청이 들어올 때 모두 통과할 수 있습니다. 그래서 양쪽 투표 배열에 사용자 ID가 없고 아직 종료 전이라는 조건을 `findOneAndUpdate`에 넣고 `$addToSet`으로 한 번에 갱신했습니다. 수정 API도 투표 배열을 저장하지 않고 편집 필드만 `$set`하여 동시에 들어온 투표를 오래된 문서로 덮어쓰지 않게 했습니다.

### Q7. MongoDB를 선택한 이유는 무엇인가요?

사용자 취향 설정, 대화 메시지, 게시글 상세, 댓글, 후기처럼 배열과 하위 객체가 많은 데이터가 중심이어서 문서 구조가 개발 초기에 빠르게 맞았습니다. 한 게시글 상세를 한 번에 읽기도 편했습니다. 대신 후기 증가와 반응 동시성에는 중첩 문서가 불리하므로 규모가 커지면 후기·댓글·반응을 분리할 계획입니다.

### Q8. 비밀번호는 안전하게 저장되나요?

서버 DB에는 bcrypt cost 12 해시로 저장하며 원문은 응답하지 않습니다. JWT secret과 API 키는 환경변수로 관리합니다. 다만 코드 리뷰에서 원격 로그인 비밀번호가 Flutter 사용자 객체에 다시 들어가 로컬 캐시에 저장되는 문제를 확인했습니다. 따라서 현재 상태를 완전히 안전하다고 말할 수 없고, 원격 모델에서 password 필드를 제거하는 것이 최우선 개선입니다.

### Q9. JWT가 있는데 모든 기능이 안전한가요?

아닙니다. 사용자 정보와 픽쇼츠 API는 JWT를 검사하지만 현재 게시글, 좋아요, 후기 일부는 클라이언트가 보낸 사용자 ID를 신뢰합니다. 이 값은 위조할 수 있습니다. 모든 변경 API에 `requireAuth`를 적용하고 작성자 판단은 body가 아니라 토큰의 `sub`로 해야 합니다.

### Q10. 외부 API 장애에 어떻게 대응했나요?

각 요청에 타임아웃을 두고, 바코드 제공자들은 개별 try/catch로 격리해 한 제공자가 실패해도 다른 결과를 사용할 수 있게 했습니다. 편봇은 AI 오류 시 로컬 분석을 반환하고, 추천용 카탈로그 같은 보조 요청의 실패는 주 화면을 막지 않습니다. 찾지 못한 바코드는 실패 횟수와 오류를 별도 컬렉션에 저장해 나중에 관찰할 수 있습니다.

### Q11. 로딩이 길 때 원인을 어떻게 확인해야 하나요?

직감만으로 데이터가 많다고 결론 내리면 안 됩니다. 브라우저 Network 탭에서 요청별 대기 시간, 응답 크기, HTTP 상태를 보고 서버 로그와 DB 쿼리 시간을 비교해야 합니다. Flutter DevTools로 렌더링 프레임과 메모리를 확인하면 네트워크 대기인지 Base64 이미지 디코딩인지 구분할 수 있습니다. 편pick에서는 카탈로그 최대 1000건과 Base64 이미지가 병목 후보이므로 응답 크기와 이미지 API 시간을 우선 측정하겠습니다.

### Q12. 실패했을 때 원래 상태로 돌아가는 예가 있나요?

좋아요 UI가 예입니다. 사용자가 누르면 즉시 낙관적으로 변경하지만 서버 요청 실패 시 이전 `Post` 객체로 롤백하고 안내를 보여줍니다. 사용자 프로필 저장도 먼저 화면 상태를 바꾼 후 저장이 실패하면 이전 사용자로 복원합니다. 코드 수정 자체는 Git 커밋 단위로 보관되어 특정 커밋에서 새 브랜치를 만들거나 변경 커밋만 되돌릴 수 있습니다.

### Q13. 왜 POST가 GET보다 무조건 안전하지 않나요?

메서드 이름은 목적을 표현할 뿐 암호화를 제공하지 않습니다. HTTP의 POST body도 네트워크에서 노출될 수 있고 브라우저·서버 로그나 악성 스크립트가 읽을 수 있습니다. HTTPS로 전송 구간을 암호화해야 하며, 별도로 인증·인가·입력 검증·안전한 저장이 필요합니다.

### Q14. 테스트에서 가장 중요하게 본 것은 무엇인가요?

단순 화면 렌더링뿐 아니라 보안과 동시성 경계를 봤습니다. in-memory MongoDB 서버에서 다른 사용자가 결과 작성자 ID를 위조해도 볼 수 없는지, 동시에 제목 수정과 투표를 해도 투표가 사라지지 않는지, 중복 투표가 막히는지를 검증했습니다. 테스트 환경에서는 `MONGO_URI`와 `OPENAI_API_KEY`를 빈 값으로 강제해 운영 시스템을 건드리지 않게 했습니다.

### Q15. 지금 다시 만든다면 가장 먼저 무엇을 바꾸겠습니까?

첫째, 원격 사용자 모델에서 평문 비밀번호를 제거합니다. 둘째, 모든 변경 API에 JWT를 적용합니다. 셋째, 이미지 저장을 객체 스토리지로 옮깁니다. 넷째, 반응을 독립 컬렉션과 unique 인덱스로 바꿉니다. 그 다음 백엔드를 TypeScript와 요청 스키마 검증 구조로 옮기고 추천 로직도 서버 서비스 계층으로 분리하겠습니다.

---

## 22. 실제 시연 시나리오

### 시나리오 A: 바코드

1. 상품 바코드를 카메라에 맞춘다.
2. 인식된 숫자와 지원 길이를 설명한다.
3. 서버에서 크롤러 DB와 캐시를 먼저 찾는다고 말한다.
4. 없으면 HACCP와 OpenFoodFacts를 병렬 조회한다고 설명한다.
5. 상품명이 검색창 또는 픽쇼츠 후보에 들어오는 결과를 보여준다.
6. 같은 바코드를 다시 조회하며 캐시의 이점을 설명한다.

### 시나리오 B: 편봇

1. “5천 원 이하로 매콤한 야식 추천해 줘”를 입력한다.
2. 최대 예산으로 해석된다고 설명한다.
3. 가격 범위 전체가 5천 원 이하인 게시글만 남는다고 말한다.
4. 초기 취향, 좋아요, 투표, 상황 점수가 합산된다고 설명한다.
5. 추천 카드가 실제 커뮤니티 게시글로 연결되는 것을 보여준다.
6. OpenAI가 상품을 만든 것이 아니라 선택된 후보를 말로 표현한 것이라고 강조한다.

### 시나리오 C: 픽쇼츠 동시성

1. 두 선택지 중 하나에 투표한다.
2. 결과가 잠시 표시되고 다음 카드로 이동하는 UI를 보여준다.
3. 같은 매치에 다시 투표할 수 없는 서버 조건을 설명한다.
4. 종료된 투표 결과가 작성자에게만 보이는 권한 처리를 설명한다.

---

## 23. 과장하면 안 되는 표현

면접에서 다음 표현은 현재 코드와 맞지 않는다.

| 피해야 할 말 | 정확한 말 |
|---|---|
| “TypeScript 백엔드입니다.” | “현재 백엔드는 JavaScript이고 프론트는 정적 타입 Dart입니다.” |
| “비밀번호는 render.yaml에 암호화 저장합니다.” | “서버 DB에는 bcrypt 해시, 서버 비밀값은 Render 환경변수에 저장합니다.” |
| “모든 API가 JWT로 안전합니다.” | “사용자·픽쇼츠는 보호하지만 게시글 계열 일부는 개선이 필요합니다.” |
| “HACCP 정보를 MongoDB와 직접 연결했습니다.” | “서버가 HACCP API를 호출하고 정규화한 결과를 MongoDB에 캐시합니다.” |
| “AI가 상품을 추천합니다.” | “코드가 후보를 필터·랭킹하고 AI는 상황 분석과 문장화를 보조합니다.” |
| “바코드 사진을 DB에 저장합니다.” | “기기에서 바코드 숫자를 인식하고 서버에는 코드만 요청합니다.” |
| “데이터가 많아서 느리다고 직감했습니다.” | “Network·서버 로그·쿼리·응답 크기로 병목을 확인해야 합니다.” |
| “POST라서 안전합니다.” | “HTTPS, 인증, 인가, 검증이 함께 있어야 안전합니다.” |

---

## 24. 코드 읽기 지도

| 주제 | 파일 | 핵심 함수/클래스 |
|---|---|---|
| 서버 전체 | `backend/server.js` | 스키마, API, 크롤러, 인증, 바코드 |
| 투표 취향·AI 프롬프트 | `backend/bot_dialogue.js` | `buildVotePreferences`, `eligibleCandidates` |
| 이미지 프록시 | `backend/image_proxy.js` | `imageProxy` |
| 앱 루트·상태 롤백 | `frontend/pyeonpick_app/lib/src/app.dart` | `_handleUserChanged` |
| 환경 분기 | `frontend/pyeonpick_app/lib/src/core/app_environment.dart` | `AppEnvironment` |
| API repository | `.../repositories/remote_post_repository.dart` | REST 호출·JSON 변환 |
| repository 추상화 | `.../repositories/post_repository.dart` | remote/mock 인터페이스 |
| 편봇·커뮤니티·바코드 UI | `.../screens/home_screen.dart` | `_buildBotReply`, `_scorePost` |
| 픽쇼츠 | `.../screens/combination_battle_screen.dart` | 생성·투표·스캐너 UI |
| 예산 해석 | `.../services/bot_budget_rules.dart` | `parseMention`, `allowsPrice` |
| 편봇 서버 호출 | `.../services/bot_situation_analyzer.dart` | analyze/reply, 투표 점수 |
| 사용자 모델 | `.../models/pyeon_user.dart` | 초기 취향·칼로리 범위 |
| 게시글 모델 | `.../models/post.dart` | 후기·댓글·상세 모델 |
| 배포 | `Dockerfile`, `render.yaml` | 멀티스테이지·환경변수 |
| 자동 크롤러 | `.github/workflows/refresh-convenience-products.yml` | 일일 wake-up |
| 백엔드 테스트 | `backend/*.test.js` | 단위·통합 테스트 |
| Flutter 테스트 | `frontend/pyeonpick_app/test/` | 위젯·서비스·모델 테스트 |

---

## 25. 최종 요약

편pick의 핵심은 “AI 앱”이라는 이름보다 데이터와 제약을 통제하는 방식에 있다. 바코드에서는 출처 우선순위와 정확 일치 검증, 추천에서는 가격 선필터와 설명 가능한 점수, 목록에서는 생성 시각 기반 커서, 투표에서는 조건부 원자 갱신, 크롤러에서는 DB 기반 스케줄을 사용했다. 이 선택들은 실제 오류와 동시성, 외부 서비스 실패, 배포 환경 재시작을 고려한 결과다.

동시에 현재 코드는 원격 비밀번호 캐시, 게시글 API 인가, 이미지 프록시 SSRF, 반응 데이터 일관성, Base64 이미지 확장성이라는 분명한 기술 부채를 갖고 있다. 면접에서는 이를 숨기지 말고 “무엇을 확인했고, 왜 위험하며, 어떤 순서로 고칠 것인지”까지 답하는 것이 오히려 코드 이해도를 보여준다.

가장 압축된 결론은 다음과 같다.

> 편pick은 Flutter와 Express, MongoDB를 이용한 편의점 추천 서비스이며, 코드가 실제 데이터와 예산 제약을 통제하고 AI는 보조적으로 사용합니다. HACCP 우선 상품 통합, 설명 가능한 추천 점수, 안정적인 커서 페이지네이션, 원자적 픽쇼츠 투표, DB 기반 크롤러 스케줄이 핵심 구현입니다. 현재 보안과 확장성의 한계도 코드 리뷰로 확인했고, 전 API JWT 적용, 평문 캐시 제거, 객체 스토리지와 원자적 반응 모델 도입을 우선 개선 과제로 두고 있습니다.
