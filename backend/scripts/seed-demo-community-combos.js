require("dotenv").config({ path: require("path").join(__dirname, "..", ".env") });

const crypto = require("crypto");
const bcrypt = require("bcryptjs");
const mongoose = require("mongoose");

const SEED_SOURCE = "demo-combo:v2";

const people = [
  ["6f0000000000000000000001", "demo_noyeonwoo", "노연우", "여자"],
  ["6f0000000000000000000002", "demo_kimtaehoon", "김태훈", "남자"],
  ["6f0000000000000000000003", "demo_leemingyu", "이민규", "남자"],
  ["6f0000000000000000000004", "demo_imchanryeol", "임찬렬", "남자"],
  ["6f0000000000000000000005", "demo_jinyerin", "진예린", "여자"],
  ["6f0000000000000000000006", "demo_leedayeon", "이다연", "여자"],
  ["6f0000000000000000000007", "demo_kimgyuri", "김규리", "여자"],
  ["6f0000000000000000000008", "demo_parksubin", "박수빈", "여자"],
  ["6f0000000000000000000009", "demo_choihyunwoo", "최현우", "남자"],
  ["6f0000000000000000000010", "demo_jungharin", "정하린", "여자"],
  ["6f0000000000000000000011", "demo_ohsejin", "오세진", "남자"],
  ["6f0000000000000000000012", "demo_hanyujin", "한유진", "남자"],
].map(([id, username, nickname, gender]) => ({ id, username, nickname, gender }));

const combos = [
  {
    key: "salad-shrimp-burger",
    author: 0,
    title: "저당 발사믹 샐러드 + 통새우 치즈버거",
    products: ["샐)저당발사믹샐러드", "햄)통새우치즈버거"],
    content: "버거만 먹으면 조금 묵직한데 샐러드를 같이 먹으니까 끝까지 덜 느끼했어요. 발사믹은 한 번에 다 붓지 않는 게 더 잘 맞았습니다.",
    price: 7900,
    calories: 690,
    categories: ["저칼로리", "짭짤", "시간절약", "트렌드"],
    situationTags: ["CU 신상", "CU PB", "점심 대용"],
    steps: ["샐러드에 발사믹을 절반만 넣어요.", "버거 한입 뒤 샐러드를 번갈아 먹어요."],
    tip: "버거를 먼저 데우고 샐러드는 차갑게 두는 편이 좋아요.",
    review: ["새우버거가 짠 편이라 샐러드랑 같이 먹으니 딱 맞았어요.", "생각보다 든든해서 점심으로 괜찮았어요."],
    comment: "발사믹 적게 넣는 거 완전 공감해요.",
    tastes: [2, 4, 3, 4],
    majority: "여자",
  },
  {
    key: "corn-tuna-iced-coffee",
    author: 1,
    title: "콘참치마요 삼각김밥 + 아샷추",
    products: ["빅삼)콘참치마요제주", "26del)아샷추230"],
    content: "수업 사이에 빨리 먹으려고 골랐는데 콘참치가 고소하고 아샷추가 입안을 정리해줘서 의외로 잘 맞았어요. 단맛은 꽤 있는 편입니다.",
    price: 3600,
    calories: 410,
    categories: ["달달", "새콤", "가성비", "시간절약"],
    situationTags: ["CU 신상", "CU PB", "등교길 추천"],
    steps: ["삼각김밥을 먼저 반 정도 먹어요.", "아샷추는 얼음이 조금 녹은 뒤 마셔요."],
    tip: "너무 달게 느껴지면 아샷추에 얼음을 더 넣어도 좋아요.",
    review: ["참치마요 뒤에 복숭아 향이 와서 은근 중독적이에요.", "바쁠 때 먹기 편하고 가격도 부담 없었어요."],
    comment: "아샷추랑 삼김 조합은 처음 보는데 궁금하네요.",
    tastes: [4, 1, 4, 3],
    majority: "남자",
  },
  {
    key: "cream-pasta-plum-zero",
    author: 2,
    title: "베이컨 크림 스파게티 + 매실 에이드 제로",
    products: ["면)베이컨크림스파게티", "PBICK)매실에이드제로P410"],
    content: "크림 파스타가 진해서 중간부터 조금 느끼했는데 매실 에이드가 확실히 잡아줬어요. 탄산 대신 새콤한 음료 찾을 때 괜찮은 조합입니다.",
    price: 6500,
    calories: 720,
    categories: ["새콤", "짭짤", "시간절약", "트렌드"],
    situationTags: ["CU 신상", "CU PB", "저녁 대용"],
    steps: ["파스타를 충분히 데운 뒤 한 번 섞어요.", "음료는 차갑게 마셔요."],
    tip: "파스타는 표시 시간보다 10초 덜 데우면 덜 마릅니다.",
    review: ["매실 맛이 생각보다 세서 크림이랑 밸런스가 좋았어요.", "양은 저녁 한 끼로 무난했어요."],
    comment: "느끼한 거 잘 못 먹는데 이 조합이면 가능할 듯해요.",
    tastes: [2, 2, 4, 4],
    majority: "남자",
  },
  {
    key: "sweet-spicy-chicken-coffee",
    author: 3,
    title: "맵달 양념 닭강정 + 스위트 아메리",
    products: ["도)맵달양념닭강정", "26del)스위트아메리230"],
    content: "닭강정 소스가 매콤달콤해서 그냥 커피보다 살짝 단 아메리카노가 더 잘 어울렸어요. 공부하다 당 떨어질 때 먹기 좋았습니다.",
    price: 6200,
    calories: 640,
    categories: ["매콤", "달달", "호불호", "트렌드"],
    situationTags: ["CU 신상", "CU PB", "공부할 때 추천"],
    steps: ["닭강정을 바삭해질 정도로 데워요.", "커피는 얼음을 넣어 차갑게 준비해요."],
    tip: "소스가 진해서 커피는 한 번에 많이 마시지 않는 게 좋아요.",
    review: ["매운맛이 오래 남지 않아서 계속 손이 갔어요.", "단 커피 싫어하면 호불호는 있을 것 같아요."],
    comment: "도서관 쉬는 시간에 딱 먹기 좋은 조합이네요.",
    tastes: [4, 4, 2, 3],
    majority: "남자",
  },
  {
    key: "corn-sandwich-strawberry",
    author: 4,
    title: "대만식 옥수수 크림 샌드 + 오구 딸기타임",
    products: ["샌)대만식옥수수크림샌드", "PB)오구딸기타임200ml"],
    content: "옥수수 크림이 생각보다 담백해서 딸기우유랑 먹어도 과하게 달지 않았어요. 아침에 입맛 없을 때 부드럽게 넘어가는 편입니다.",
    price: 4300,
    calories: 480,
    categories: ["달달", "가성비", "시간절약", "트렌드"],
    situationTags: ["CU 신상", "CU PB", "세븐일레븐 PB", "아침 대용"],
    steps: ["샌드는 데우지 않고 차갑게 먹어요.", "딸기우유를 중간중간 곁들여요."],
    tip: "둘 다 차가우면 단맛이 덜 세게 느껴져요.",
    review: ["크림이 느끼할 줄 알았는데 옥수수 식감이 있어서 괜찮았어요.", "아침에 반만 먹어도 생각보다 든든해요."],
    comment: "딸기우유 좋아하면 실패 없을 것 같아요.",
    tastes: [5, 1, 2, 2],
    majority: "여자",
  },
  {
    key: "eel-rice-pork",
    author: 5,
    title: "보양 장어삼계밥 + 포차24 머릿고기",
    products: ["도)보양장어삼계밥", "포차24)머릿고기165g"],
    content: "둘 다 묵직해서 한 번에 다 먹기보다는 둘이 나눠 먹기 좋았어요. 장어 소스가 달큰하고 머릿고기는 담백해서 야식보다는 저녁 느낌입니다.",
    price: 11900,
    calories: 980,
    categories: ["짭짤", "호불호", "트렌드"],
    situationTags: ["CU 신상", "CU PB", "emart24 신상", "emart24 PB", "저녁 대용"],
    steps: ["밥을 먼저 충분히 데워요.", "머릿고기는 전자레인지에 짧게만 데워 곁들여요."],
    tip: "두 명이 먹는다면 김치 하나만 추가해도 충분해요.",
    review: ["양이 많아서 둘이 나눠 먹으니 딱 맞았어요.", "머릿고기 식감 때문에 취향은 좀 탈 것 같아요."],
    comment: "가격은 있지만 제대로 한 끼 먹고 싶을 때 괜찮겠어요.",
    tastes: [3, 2, 2, 5],
    majority: "여자",
  },
  {
    key: "spicy-burger-mango-milk",
    author: 6,
    title: "불닭마요 통치킨버거 + 망고우유",
    products: ["햄)불닭마요통치킨버거", "성수310)망고우유300ml"],
    content: "버거 첫입은 꽤 매운데 망고우유가 바로 눌러줘서 끝까지 먹기 편했어요. 우유가 달아서 매운맛보다 맵단 쪽에 가깝습니다.",
    price: 5900,
    calories: 760,
    categories: ["매콤", "달달", "가성비", "호불호"],
    situationTags: ["CU 신상", "CU PB", "emart24 PB", "야식 추천"],
    steps: ["버거를 포장지째 짧게 데워요.", "망고우유는 최대한 차갑게 마셔요."],
    tip: "매운맛에 약하면 우유를 먼저 한 모금 마셔도 좋아요.",
    review: ["불닭마요가 꽤 매운데 망고 향이 의외로 잘 어울려요.", "맵단 좋아하면 다시 살 조합이에요."],
    comment: "망고우유가 매운맛 잡아주는지 궁금했는데 되네요.",
    tastes: [4, 5, 2, 3],
    majority: "여자",
  },
  {
    key: "cheese-tteokbokki-sandwich",
    author: 7,
    title: "치즈쏘옥 떡볶이 + 햄치즈 샌드",
    products: ["응급실)치즈쏘옥떡볶이300g", "샌)햄치즈샌드"],
    content: "떡볶이 소스를 샌드 끝부분에 살짝 찍어 먹으니까 분식집 토스트 같은 맛이 났어요. 소스를 많이 묻히면 금방 짜져서 조금씩 먹는 게 낫습니다.",
    price: 6800,
    calories: 830,
    categories: ["매콤", "짭짤", "호불호", "트렌드"],
    situationTags: ["emart24 신상", "emart24 PB", "CU 신상", "CU PB", "야식 추천"],
    steps: ["떡볶이를 먼저 데워 치즈를 섞어요.", "샌드는 차갑게 두고 소스에 조금씩 찍어 먹어요."],
    tip: "샌드를 전부 담그지 말고 모서리만 찍어 먹는 게 좋아요.",
    review: ["떡볶이만 먹을 때보다 빵이 있어서 덜 매웠어요.", "탄수화물 조합이라 배는 확실히 불러요."],
    comment: "분식집 토스트 느낌이라는 말이 딱이네요.",
    tastes: [3, 4, 2, 5],
    majority: "여자",
  },
  {
    key: "mushroom-burger-salad",
    author: 8,
    title: "트러플 머쉬룸 버거 + 저당 발사믹 샐러드",
    products: ["겟모닝)트러플머쉬룸버거", "샐)저당발사믹샐러드"],
    content: "버섯 향이 진한 편이라 샐러드랑 같이 먹으니 훨씬 깔끔했어요. 점심에 먹고도 너무 무겁지 않아서 다시 고를 것 같습니다.",
    price: 8100,
    calories: 650,
    categories: ["저칼로리", "짭짤", "시간절약", "트렌드"],
    situationTags: ["CU 신상", "CU PB", "점심 대용"],
    steps: ["버거는 포장지째 데워요.", "샐러드 소스는 먹기 직전에 섞어요."],
    tip: "버섯 향이 강하니 샐러드부터 한입 먹으면 밸런스가 좋아요.",
    review: ["트러플 향이 세지만 샐러드가 잘 잡아줘요.", "채소까지 같이 먹는 느낌이라 덜 부담스러웠어요."],
    comment: "회사 점심으로 따라 해볼 만하네요.",
    tastes: [2, 1, 3, 4],
    majority: "남자",
  },
  {
    key: "potato-pizza-choco-milk",
    author: 9,
    title: "더블 감자 베이컨 피자 + 오구 초코타임",
    products: ["PBICK)더블감자베이컨피자", "PB)오구초코타임200ml"],
    content: "감자 때문에 피자가 짭짤하고 묵직한데 초코우유가 디저트처럼 마무리해줘요. 영화 볼 때 천천히 먹기 좋은 조합이었습니다.",
    price: 7200,
    calories: 890,
    categories: ["달달", "짭짤", "호불호", "트렌드"],
    situationTags: ["CU 신상", "CU PB", "세븐일레븐 PB", "야식 추천"],
    steps: ["피자는 가장자리가 바삭해질 때까지 데워요.", "초코우유는 피자를 반쯤 먹은 뒤 마셔요."],
    tip: "한 번에 먹기 무거우면 피자를 두 조각 남겨도 충분해요.",
    review: ["감자 토핑이 포슬해서 생각보다 식감이 좋았어요.", "단짠 조합 좋아하지만 한 번에 다 먹기는 조금 무거워요."],
    comment: "영화 보면서 먹으면 진짜 금방 없어질 듯해요.",
    tastes: [5, 1, 2, 5],
    majority: "여자",
  },
];

function profileVisibility() {
  return {
    username: false,
    likes: true,
    dislikes: false,
    saved: false,
    myPosts: true,
    picks: true,
    pickedBy: true,
  };
}

async function seedPeople(users) {
  for (const person of people) {
    const id = new mongoose.Types.ObjectId(person.id);
    const collision = await users.findOne({
      $or: [{ username: person.username }, { nickname: person.nickname }],
      _id: { $ne: id },
    });
    if (collision) {
      throw new Error(`Demo user collision: ${person.nickname}`);
    }
    await users.updateOne(
      { _id: id },
      {
        $setOnInsert: {
          username: person.username,
          passwordHash: bcrypt.hashSync(crypto.randomBytes(24).toString("hex"), 12),
          profileImageUrl: null,
          memoryNotes: [],
          botMessages: [],
          archivedConversations: [],
          likedPostIds: [],
          dislikedPostIds: [],
          savedPostIds: [],
          pickedAuthorIds: [],
          battleState: {},
          battleResultReadIds: [],
          profilePublic: true,
          profileVisibility: profileVisibility(),
          createdAt: new Date(),
        },
        $set: {
          nickname: person.nickname,
          botSetup: {
            age: 20 + (Number(person.id.slice(-2)) % 7),
            gender: person.gender,
            tasteRatings: { 달달: 3, 매콤: 3, 새콤: 3, 짭짤: 3 },
            priorityValues: ["가성비", "시간절약"],
            favoriteTastes: [],
            reasons: [],
          },
          seedSource: SEED_SOURCE,
          updatedAt: new Date(),
        },
      },
      { upsert: true }
    );
  }
}

function postReview(combo, reviewer, index, createdAt) {
  const [sweet, spicy, sour, salty] = combo.tastes;
  return {
    id: `${SEED_SOURCE}:${combo.key}:review:${index + 1}`,
    authorId: reviewer.id,
    authorNickname: reviewer.nickname,
    text: combo.review[index],
    rating: index === 0 ? 5 : 4,
    tags: index === 0 ? ["기대 이상이에요"] : ["또 먹고 싶어요"],
    sweet,
    salty,
    spicy,
    sour,
    caution: "",
    createdAt,
  };
}

async function seedPosts(db) {
  const posts = db.collection("posts");
  const users = db.collection("users");
  const now = new Date();
  const createdPostIds = [];

  for (const [index, combo] of combos.entries()) {
    const author = people[combo.author];
    const reviewerA = people[(combo.author + 3) % people.length];
    const reviewerB = people[(combo.author + 7) % people.length];
    const createdAt = new Date(now.getTime() - index * 37 * 60 * 1000);
    const sameGender = people.filter(
      (person) => person.gender === combo.majority && person.id !== author.id
    );
    const otherGender = people.filter(
      (person) => person.gender !== combo.majority && person.id !== author.id
    );
    const likers = [...sameGender.slice(0, 5), ...otherGender.slice(0, 1)];
    const likeEvents = likers.map((person, likeIndex) => ({
      userId: person.id,
      createdAt: new Date(createdAt.getTime() + (likeIndex + 1) * 4 * 60 * 1000),
    }));
    const key = `${SEED_SOURCE}:${combo.key}`;
    const document = {
      authorId: author.id,
      authorNickname: author.nickname,
      authorProfileImageUrl: null,
      title: combo.title,
      content: combo.content,
      priceMin: combo.price,
      priceMax: combo.price,
      categories: combo.categories,
      likes: 10 + (index % 7),
      likeEvents,
      dislikes: index % 4 === 3 ? 1 : 0,
      comments: [
        {
          authorId: reviewerA.id,
          authorNickname: reviewerA.nickname,
          authorProfileImageUrl: null,
          text: combo.comment,
          createdAt: new Date(createdAt.getTime() + 11 * 60 * 1000),
        },
      ],
      reviews: [
        postReview(combo, reviewerA, 0, new Date(createdAt.getTime() + 18 * 60 * 1000)),
        postReview(combo, reviewerB, 1, new Date(createdAt.getTime() + 26 * 60 * 1000)),
      ],
      calories: combo.calories,
      rating: 4.5,
      imageData: null,
      imageUrl: `/assets/assets/seed-combos/combo-${String(index + 1).padStart(2, "0")}.jpg`,
      imageDatas: [],
      imageUrls: [`/assets/assets/seed-combos/combo-${String(index + 1).padStart(2, "0")}.jpg`],
      details: {
        usedProducts: combo.products,
        eatingSteps: combo.steps,
        tips: [combo.tip],
        cautions: [],
        situationTags: combo.situationTags,
        reviewPoints: ["맛 조합", "가격 대비 만족도", "재구매 의사"],
        prepTimeTag: key,
      },
      likedByMe: false,
      dislikedByMe: false,
      topFiveEnteredAt: null,
      topWorstEnteredAt: null,
      seedSource: SEED_SOURCE,
      createdAt,
      updatedAt: now,
    };

    const result = await posts.findOneAndUpdate(
      { "details.prepTimeTag": key },
      { $set: document },
      { upsert: true, returnDocument: "after" }
    );
    const post = result?.value || result;
    const postId = String(post._id);
    createdPostIds.push(postId);

    await users.updateMany(
      { _id: { $in: likers.map((person) => new mongoose.Types.ObjectId(person.id)) } },
      { $addToSet: { likedPostIds: postId }, $set: { updatedAt: now } }
    );
  }

  return createdPostIds;
}

async function main() {
  if (process.env.CONFIRM_DEMO_SEED !== "true") {
    throw new Error("Set CONFIRM_DEMO_SEED=true to insert the demo community data.");
  }
  const mongoUri = String(process.env.MONGO_URI || "").trim();
  if (!mongoUri) throw new Error("MONGO_URI is required.");

  await mongoose.connect(mongoUri);
  const db = mongoose.connection.db;
  await seedPeople(db.collection("users"));
  const postIds = await seedPosts(db);
  console.log(
    JSON.stringify(
      { seedSource: SEED_SOURCE, users: people.length, posts: postIds.length, postIds },
      null,
      2
    )
  );
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await mongoose.disconnect().catch(() => {});
  });
