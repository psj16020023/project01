require("dotenv").config({ path: require("path").join(__dirname, "..", ".env") });

const mongoose = require("mongoose");

const seedUserIds = {
  cu: "683ab41f0a22b15a8a101001",
  emart24: "683ab41f0a22b15a8a101002",
  seven: "683ab41f0a22b15a8a101004",
  editor: "683ab41f0a22b15a8a101007",
};

const authorProfiles = {
  cu: {
    authorId: seedUserIds.cu,
    authorNickname: "CU 매대픽",
    authorProfileImageUrl:
      "https://images.unsplash.com/photo-1542838132-92c53300491e?auto=format&fit=crop&w=300&q=80",
  },
  emart24: {
    authorId: seedUserIds.emart24,
    authorNickname: "emart24 매대픽",
    authorProfileImageUrl:
      "https://images.unsplash.com/photo-1604719312566-8912e9227c6a?auto=format&fit=crop&w=300&q=80",
  },
  seven: {
    authorId: seedUserIds.seven,
    authorNickname: "7-Eleven 매대픽",
    authorProfileImageUrl:
      "https://images.unsplash.com/photo-1583258292688-d0213dc5a3a8?auto=format&fit=crop&w=300&q=80",
  },
  editor: {
    authorId: seedUserIds.editor,
    authorNickname: "편픽 에디터",
    authorProfileImageUrl:
      "https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=300&q=80",
  },
};

const combos = [
  {
    key: "cu-summer-zero-bagel",
    author: "cu",
    title: "매실 에이드 제로 + 어니언 크림 베이글",
    products: [
      { collection: "cuproducts", name: "PBICK)매실에이드제로P410" },
      { collection: "cuproducts", name: "겟모닝)어니언크림베이글" },
    ],
    content: "상큼한 제로 음료랑 크림 베이글 조합. 아침에 들고 나가기 좋은 쪽.",
    categories: ["아침", "달달", "시간절약"],
    likes: 12,
  },
  {
    key: "cu-spicy-burger-jinmichae",
    author: "cu",
    title: "양념 통치킨 버거 + 땅콩버터 진미채",
    products: [
      { collection: "cuproducts", name: "햄)양념통치킨버거" },
      { collection: "cuproducts", name: "PBICK땅콩버터진미채" },
    ],
    content: "매콤한 버거에 고소한 안주류를 붙인 묵직한 조합.",
    categories: ["야식", "매콤", "든든함"],
    likes: 10,
  },
  {
    key: "cu-zero-jinmichae",
    author: "cu",
    title: "매실 에이드 제로 + 땅콩버터 진미채",
    products: [
      { collection: "cuproducts", name: "PBICK)매실에이드제로P410" },
      { collection: "cuproducts", name: "PBICK땅콩버터진미채" },
    ],
    content: "달짝지근한 안주에 깔끔한 제로 음료로 마무리.",
    categories: ["간식", "달달", "짭짤"],
    likes: 8,
  },
  {
    key: "emart24-tteokbokki-skin",
    author: "emart24",
    title: "치즈쏘옥 떡볶이 + 매콤 껍데기",
    products: [
      { collection: "convenienceproducts", name: "응급실)치즈쏘옥떡볶이300g" },
      { collection: "convenienceproducts", name: "포차24)매콤껍데기200g" },
    ],
    content: "매운맛 두 개를 붙인 야식 조합. 치즈가 있어서 생각보다 잘 넘어감.",
    categories: ["야식", "매콤", "든든함"],
    likes: 14,
  },
  {
    key: "emart24-mango-tteokbokki",
    author: "emart24",
    title: "망고 우유 + 치즈쏘옥 떡볶이",
    products: [
      { collection: "convenienceproducts", name: "성수310)망고우유300ml" },
      { collection: "convenienceproducts", name: "응급실)치즈쏘옥떡볶이300g" },
    ],
    content: "떡볶이 매운맛을 망고 우유로 눌러주는 조합.",
    categories: ["매콤", "달달", "간식"],
    likes: 11,
  },
  {
    key: "emart24-pocha-pork-pair",
    author: "emart24",
    title: "매콤 껍데기 + 머릿고기",
    products: [
      { collection: "convenienceproducts", name: "포차24)매콤껍데기200g" },
      { collection: "convenienceproducts", name: "포차24)머릿고기165g" },
    ],
    content: "편의점에서 바로 만드는 포차 느낌. 야식용으로 강한 조합.",
    categories: ["야식", "짭짤", "매콤"],
    likes: 9,
  },
  {
    key: "seven-strawberry-choco",
    author: "seven",
    title: "오구 딸기타임 + 오구 초코타임",
    products: [
      { collection: "convenienceproducts", name: "PB)오구딸기타임200ml" },
      { collection: "convenienceproducts", name: "PB)오구초코타임200ml" },
    ],
    content: "딸기랑 초코를 같이 고르는 디저트 음료 조합.",
    categories: ["디저트", "달달", "간식"],
    likes: 7,
  },
  {
    key: "mixed-zero-mango",
    author: "editor",
    title: "매실 에이드 제로 + 망고 우유",
    products: [
      { collection: "cuproducts", name: "PBICK)매실에이드제로P410" },
      { collection: "convenienceproducts", name: "성수310)망고우유300ml" },
    ],
    content: "상큼한 제로랑 부드러운 우유를 같이 잡는 음료 조합.",
    categories: ["음료", "달달", "새콤"],
    likes: 6,
  },
];

function priceToNumber(value) {
  const parsed = Number(String(value || "").replace(/[^0-9]/g, ""));
  return Number.isFinite(parsed) ? parsed : 0;
}

function labelsFor(product) {
  return [
    ...(product.isNewFlag || product.isNewByDiff
      ? [`${product.store || "CU"} 신상`]
      : []),
    ...(product.isPb ? [`${product.store || "CU"} PB`] : []),
  ];
}

async function main() {
  const mongoUri = String(process.env.MONGO_URI || "").trim();
  if (!mongoUri) {
    throw new Error("MONGO_URI is required. Add it to backend/.env first.");
  }

  await mongoose.connect(mongoUri);
  const db = mongoose.connection.db;
  const posts = db.collection("posts");

  let created = 0;
  let skipped = 0;
  const now = new Date();

  for (const [index, combo] of combos.entries()) {
    const existing = await posts.findOne({
      "details.prepTimeTag": `curated:${combo.key}`,
    });
    if (existing) {
      skipped += 1;
      continue;
    }

    const products = [];
    for (const productRef of combo.products) {
      const product = await db
        .collection(productRef.collection)
        .findOne({ name: productRef.name });
      if (product) products.push(product);
    }
    if (products.length === 0) {
      skipped += 1;
      continue;
    }

    const priceTotal = products.reduce(
      (sum, product) => sum + priceToNumber(product.price),
      0
    );
    const labelTags = [...new Set(products.flatMap(labelsFor))];
    const imageUrls = products
      .map((product) => product.imageUrl)
      .filter(Boolean);
    const barcodes = products
      .map((product) => product.barcode)
      .filter(Boolean);
    const author = authorProfiles[combo.author];

    const title = products.map((product) => product.name).join(" + ");

    await posts.insertOne({
      ...author,
      title,
      content:
        `${combo.content}\n` +
        `바코드 ${barcodes.length ? barcodes.join(" / ") : "확인 전"}.`,
      priceMin: priceTotal,
      priceMax: priceTotal,
      categories: combo.categories,
      likes: combo.likes,
      dislikes: index % 4 === 0 ? 1 : 0,
      comments: [],
      reviews: [],
      calories: null,
      rating: 0,
      imageData: null,
      imageUrl: imageUrls[0] || null,
      imageDatas: [],
      imageUrls,
      details: {
        eatingSteps: ["사진 속 상품을 같이 담고, 바로 먹거나 데워서 곁들여요."],
        tips: ["상품명 밑줄은 앱 상품 DB에서 감지한 신상/PB 표시예요."],
        cautions: [],
        situationTags: labelTags,
        reviewPoints: ["조합 밸런스", "재구매 의사"],
        prepTimeTag: `curated:${combo.key}`,
      },
      likedByMe: false,
      dislikedByMe: false,
      topFiveEnteredAt: null,
      topWorstEnteredAt: null,
      createdAt: new Date(now.getTime() - index * 3 * 60 * 1000),
      updatedAt: now,
    });
    created += 1;
  }

  console.log(JSON.stringify({ created, skipped }, null, 2));
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await mongoose.disconnect().catch(() => {});
  });
