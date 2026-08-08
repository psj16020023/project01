require("dotenv").config({ path: require("path").join(__dirname, "..", ".env") });

const mongoose = require("mongoose");

const seedAuthorIds = [
  "683ab41f0a22b15a8a101001",
  "683ab41f0a22b15a8a101002",
  "683ab41f0a22b15a8a101003",
  "683ab41f0a22b15a8a101004",
  "683ab41f0a22b15a8a101005",
  "683ab41f0a22b15a8a101006",
  "683ab41f0a22b15a8a101007",
];

const authors = [
  {
    id: "683ab41f0a22b15a8a101001",
    nickname: "CU 야식픽",
    image:
      "https://images.unsplash.com/photo-1556745757-8d76bdb6984b?auto=format&fit=crop&w=300&q=80",
  },
  {
    id: "683ab41f0a22b15a8a101002",
    nickname: "편의점 미식회",
    image:
      "https://images.unsplash.com/photo-1542838132-92c53300491e?auto=format&fit=crop&w=300&q=80",
  },
  {
    id: "683ab41f0a22b15a8a101003",
    nickname: "CU 매대탐험",
    image:
      "https://images.unsplash.com/photo-1604719312566-8912e9227c6a?auto=format&fit=crop&w=300&q=80",
  },
  {
    id: "683ab41f0a22b15a8a101004",
    nickname: "오늘의 씨유",
    image:
      "https://images.unsplash.com/photo-1578916171728-46686eac8d58?auto=format&fit=crop&w=300&q=80",
  },
];

const combos = [
  {
    title: "매실 에이드 제로 + 불닭마요 통치킨버거",
    products: ["PBICK)매실에이드제로P410", "햄)불닭마요통치킨버거"],
    content: "매운 버거 먹고 바로 상큼하게 눌러주는 조합. 야식인데 끝맛은 깔끔함.",
    categories: ["야식", "매콤", "새콤"],
    likes: 31,
    dislikes: 2,
  },
  {
    title: "아샷추 + 어니언 크림 베이글",
    products: ["26del)아샷추230", "겟모닝)어니언크림베이글"],
    content: "아침에 커피 대신 집기 좋은 조합. 달달한 음료랑 짭짤한 크림 베이글이 잘 맞음.",
    categories: ["아침", "달달", "시간절약"],
    likes: 28,
    dislikes: 1,
  },
  {
    title: "쿵야 김치볶음밥 참치마요 + 반반 닭강정팩",
    products: ["김)쿵야김치볶음참치마요", "도)쿵야반반닭강정팩"],
    content: "작은 김밥 하나로는 아쉬울 때 닭강정까지 붙이는 든든한 CU식 한 끼.",
    categories: ["든든함", "매콤", "점심"],
    likes: 26,
    dislikes: 2,
  },
  {
    title: "골뱅이 비빔면 + 매실 에이드 제로",
    products: ["도)별미골뱅이비빔면", "PBICK)매실에이드제로P410"],
    content: "새콤매콤한 비빔면에 제로 음료. 더운 날 편의점 앞에서 바로 생각나는 맛.",
    categories: ["매콤", "새콤", "여름"],
    likes: 24,
    dislikes: 1,
  },
  {
    title: "트러플 머쉬룸 버거 + 저당 발사믹 샐러드",
    products: ["겟모닝)트러플머쉬룸버거", "샐)저당발사믹샐러드"],
    content: "버거 먹고 싶은데 너무 무겁긴 싫을 때. 샐러드가 균형을 잡아줌.",
    categories: ["가벼움", "점심", "든든함"],
    likes: 22,
    dislikes: 0,
  },
  {
    title: "대만식 옥수수 크림샌드 + 스위트 아메리",
    products: ["샌)대만식옥수수크림샌드", "26del)스위트아메리230"],
    content: "크림샌드의 고소달달함을 커피가 정리해주는 조합. 출근길에 좋음.",
    categories: ["아침", "달달", "간식"],
    likes: 21,
    dislikes: 1,
  },
  {
    title: "보양 삼계버거 + 보양 장어 삼계밥",
    products: ["햄)보양삼계버거", "도)보양장어삼계밥"],
    content: "오늘은 제대로 배 채우겠다는 날의 CU 보양 조합. 가볍진 않은데 확실히 든든함.",
    categories: ["든든함", "점심", "고단백"],
    likes: 20,
    dislikes: 3,
  },
  {
    title: "매콤 아삭이고추 비빔밥 + 매실 에이드 제로",
    products: ["도)매콤아삭이고추비빔밥", "PBICK)매실에이드제로P410"],
    content: "매운 비빔밥 먹을 때 음료까지 한 번에 고르는 조합. 아삭한 매운맛이 포인트.",
    categories: ["매콤", "새콤", "점심"],
    likes: 19,
    dislikes: 1,
  },
  {
    title: "베이컨 크림 스파게티 + 아샷추",
    products: ["면)베이컨크림스파게티", "26del)아샷추230"],
    content: "꾸덕한 크림 파스타에 달달쌉싸름한 아샷추. 생각보다 편의점 카페 느낌 남.",
    categories: ["달달", "점심", "간식"],
    likes: 18,
    dislikes: 1,
  },
  {
    title: "밥도둑 묵은지 참치 + 더블 감자 베이컨 피자",
    products: ["김)밥도둑묵은지참치", "PBICK)더블감자베이컨피자"],
    content: "김밥으로 짭짤하게 시작하고 피자로 마무리. 둘이 나눠 먹기 좋은 조합.",
    categories: ["짭짤", "간식", "든든함"],
    likes: 17,
    dislikes: 2,
  },
  {
    title: "통새우 치즈버거 + 콘참치마요 제주",
    products: ["햄)통새우치즈버거", "빅삼)콘참치마요제주"],
    content: "버거 하나로 부족한 사람용. 삼각김밥까지 붙이면 딱 편의점 한 끼 완성.",
    categories: ["든든함", "점심", "가성비"],
    likes: 16,
    dislikes: 1,
  },
  {
    title: "햄치즈 토마토 샌드 + 아샷추",
    products: ["샌)햄치즈토마토샌드", "26del)아샷추230"],
    content: "샌드위치랑 아샷추는 실패하기 힘든 조합. 이동하면서 먹기에도 편함.",
    categories: ["아침", "시간절약", "달달"],
    likes: 15,
    dislikes: 0,
  },
  {
    title: "땅콩버터 진미채 + 매실 에이드 제로",
    products: ["PBICK땅콩버터진미채", "PBICK)매실에이드제로P410"],
    content: "짭짤고소한 안주형 상품에 상큼한 제로 음료. 늦은 밤 가볍게 집기 좋음.",
    categories: ["야식", "짭짤", "새콤"],
    likes: 14,
    dislikes: 1,
  },
  {
    title: "잠봉치즈 크루아상 샌드 + 스위트 아메리",
    products: ["샌)잠봉치즈크루아상샌드", "26del)스위트아메리230"],
    content: "빵집 느낌을 CU에서 빠르게 맞추는 조합. 커피까지 같이 잡으면 꽤 그럴듯함.",
    categories: ["아침", "달달", "간식"],
    likes: 13,
    dislikes: 0,
  },
];

function priceToNumber(value) {
  const parsed = Number(String(value || "").replace(/[^0-9]/g, ""));
  return Number.isFinite(parsed) ? parsed : 0;
}

async function main() {
  const mongoUri = String(process.env.MONGO_URI || "").trim();
  if (!mongoUri) {
    throw new Error("MONGO_URI is required. Add it to backend/.env first.");
  }

  await mongoose.connect(mongoUri);
  const db = mongoose.connection.db;
  const posts = db.collection("posts");
  const cuProducts = db.collection("cuproducts");

  const deleteResult = await posts.deleteMany({
    $or: [
      { authorId: { $in: seedAuthorIds } },
      { authorNickname: /상품봇|매대픽|편픽 에디터/ },
      { "details.prepTimeTag": /^curated:/ },
      { "details.prepTimeTag": /^cu-overhaul:/ },
    ],
  });

  let created = 0;
  const now = new Date();

  for (const [index, combo] of combos.entries()) {
    const products = [];
    for (const productName of combo.products) {
      const product = await cuProducts.findOne({ name: productName });
      if (!product) {
        throw new Error(`Missing CU product: ${productName}`);
      }
      products.push(product);
    }

    const author = authors[index % authors.length];
    const imageUrls = products.map((product) => product.imageUrl).filter(Boolean);
    const barcodes = products.map((product) => product.barcode).filter(Boolean);
    const priceTotal = products.reduce(
      (sum, product) => sum + priceToNumber(product.price),
      0
    );

    await posts.insertOne({
      authorId: author.id,
      authorNickname: author.nickname,
      authorProfileImageUrl: author.image,
      title: combo.title,
      content: `${combo.content}\n바코드 ${barcodes.join(" / ")}.`,
      priceMin: priceTotal,
      priceMax: priceTotal,
      categories: combo.categories,
      likes: combo.likes,
      dislikes: combo.dislikes,
      comments: [],
      reviews: [],
      calories: null,
      rating: 0,
      imageData: null,
      imageUrl: imageUrls[0] || null,
      imageDatas: [],
      imageUrls,
      details: {
        eatingSteps: ["CU에서 두 상품을 같이 담고, 필요한 상품만 전자레인지로 데워요."],
        tips: ["상품명 밑줄은 CU 상품 DB에서 감지한 신상/PB 표시예요."],
        cautions: [],
        situationTags: ["CU 신상", "CU PB"],
        reviewPoints: ["맛 밸런스", "가격 대비 만족도", "다시 살지"],
        prepTimeTag: `cu-overhaul:${index + 1}`,
      },
      likedByMe: false,
      dislikedByMe: false,
      topFiveEnteredAt: null,
      topWorstEnteredAt: null,
      createdAt: new Date(now.getTime() - index * 2 * 60 * 1000),
      updatedAt: now,
    });
    created += 1;
  }

  console.log(
    JSON.stringify(
      { deleted: deleteResult.deletedCount, created, preservedUserPosts: true },
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
