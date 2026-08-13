require("dotenv").config({ path: require("path").join(__dirname, "..", ".env") });

const mongoose = require("mongoose");

const STORE_CONFIGS = [
  { store: "emart24", label: "이마트24", count: 24, offset: 13 },
  { store: "GS25", label: "GS25", count: 24, offset: 17 },
  { store: "7-Eleven", label: "세븐일레븐", count: 24, offset: 11 },
];

const AUTHOR_IDS = [
  "683ab41f0a22b15a8a101001",
  "683ab41f0a22b15a8a101002",
  "683ab41f0a22b15a8a101003",
  "683ab41f0a22b15a8a101004",
  "683ab41f0a22b15a8a101005",
  "683ab41f0a22b15a8a101006",
  "683ab41f0a22b15a8a101007",
];

// Convenience-store PB feeds can include household goods. Community food posts keep only edible products.
const NON_FOOD_PATTERN = /티슈|타올|휴지|면도기|생리대|물티슈|세제|칫솔|치약|마스크|건전지|수세미|비닐|종이컵/i;
const LIGHT_PRODUCT_PATTERN = /제로|무가당|저당|고단백|단백|곤약|샐러드|콤부차|두유|아몬드/i;
const DISTINCTIVE_PRODUCT_PATTERN = /마라|곱창|닭발|껍데기|옥수수|멜론|망고|인절미|카라멜|치폴레|피치|구아바/i;

const CONTENTS = [
  "신상 코너와 PB 코너에서 함께 고르기 좋은 조합 후보예요.",
  "바로 집어 들고 간식이나 한 끼로 이어가기 좋게 묶어봤어요.",
  "상품 사진을 보며 오늘 끌리는 쪽으로 골라볼 수 있는 편의점 조합이에요.",
  "행사 상품을 발견했을 때 같이 담아보기 좋은 두 가지예요.",
  "새로 들어온 상품 위주로 구성한 빠른 편의점 장보기 후보예요.",
  "맛이 궁금한 신상과 익숙한 상품을 한 번에 비교해보기 좋은 조합이에요.",
];

function priceToNumber(value) {
  const parsed = Number(String(value || "").replace(/[^0-9]/g, ""));
  return Number.isFinite(parsed) ? parsed : 0;
}

function productLabels(product, storeLabel) {
  const labels = [];
  if (product.isNewFlag || product.isNewByDiff) labels.push(`${storeLabel} 신상`);
  if (product.isPb) labels.push(`${storeLabel} PB`);
  if ((product.tags || []).some((tag) => /1\+1|2\+1|행사/.test(String(tag)))) {
    labels.push(`${storeLabel} 행사`);
  }
  return labels;
}

function categoriesFor(products, index) {
  const names = products.map((product) => product.name).join(" ");
  const total = products.reduce((sum, product) => sum + priceToNumber(product.price), 0);
  const categories = new Set(["시간절약"]);

  if (products.some((product) => product.isNewFlag || product.isNewByDiff)) {
    categories.add("트렌드");
  }
  if (products.some((product) => product.isPb) || (total > 0 && total <= 6000)) {
    categories.add("가성비");
  }
  if (LIGHT_PRODUCT_PATTERN.test(names)) categories.add("저칼로리");
  if (index % 3 === 0 && DISTINCTIVE_PRODUCT_PATTERN.test(names)) {
    categories.add("호불호");
  }

  return Array.from(categories);
}

function sortCandidates(products) {
  return [...products].sort((left, right) => {
    const leftScore = Number(Boolean(left.isNewFlag || left.isNewByDiff)) * 4 + Number(Boolean(left.isPb)) * 2;
    const rightScore = Number(Boolean(right.isNewFlag || right.isNewByDiff)) * 4 + Number(Boolean(right.isPb)) * 2;
    return rightScore - leftScore || new Date(right.lastSeenAt || 0) - new Date(left.lastSeenAt || 0);
  });
}

async function loadCandidates(products, store) {
  const rawProducts = await products
    .find({
      store,
      imageUrl: { $type: "string", $ne: "" },
      $or: [{ isNewFlag: true }, { isNewByDiff: true }, { isPb: true }],
    })
    .project({
      name: 1,
      price: 1,
      imageUrl: 1,
      barcode: 1,
      isNewFlag: 1,
      isNewByDiff: 1,
      isPb: 1,
      tags: 1,
      lastSeenAt: 1,
    })
    .toArray();

  const seenNames = new Set();
  return sortCandidates(rawProducts).filter((product) => {
    const normalizedName = String(product.name || "").trim();
    if (!normalizedName || NON_FOOD_PATTERN.test(normalizedName) || seenNames.has(normalizedName)) {
      return false;
    }
    seenNames.add(normalizedName);
    return true;
  });
}

async function main() {
  const mongoUri = String(process.env.MONGO_URI || "").trim();
  if (!mongoUri) throw new Error("MONGO_URI is required. Add it to backend/.env first.");

  await mongoose.connect(mongoUri);
  const db = mongoose.connection.db;
  const posts = db.collection("posts");
  const products = db.collection("convenienceproducts");
  const users = await db
    .collection("users")
    .find({ _id: { $in: AUTHOR_IDS.map((id) => new mongoose.Types.ObjectId(id)) } })
    .project({ nickname: 1, profileImageUrl: 1 })
    .toArray();
  const authors = new Map(users.map((user) => [String(user._id), user]));
  const now = new Date();
  let created = 0;
  let skipped = 0;

  for (const config of STORE_CONFIGS) {
    const candidates = await loadCandidates(products, config.store);
    if (candidates.length < 2) {
      console.warn(`Not enough eligible ${config.label} products to seed posts.`);
      continue;
    }

    const postCount = Math.min(config.count, candidates.length);
    for (let index = 0; index < postCount; index += 1) {
      const primary = candidates[index];
      const companion = candidates[(index + config.offset) % candidates.length];
      const selectedProducts = primary.name === companion.name ? [primary] : [primary, companion];
      const postKey = `catalog-colorful:v1:${config.store}:${index + 1}`;
      const existing = await posts.findOne({ "details.prepTimeTag": postKey });
      if (existing) {
        skipped += 1;
        continue;
      }

      const authorId = AUTHOR_IDS[(created + index) % AUTHOR_IDS.length];
      const author = authors.get(authorId);
      const priceTotal = selectedProducts.reduce((sum, product) => sum + priceToNumber(product.price), 0);
      const imageUrls = selectedProducts.map((product) => product.imageUrl).filter(Boolean);
      const labels = [...new Set(selectedProducts.flatMap((product) => productLabels(product, config.label)))];
      const barcodeText = selectedProducts.map((product) => product.barcode).filter(Boolean).join(" / ");

      await posts.insertOne({
        authorId,
        authorNickname: author?.nickname || `${config.label} 상품픽`,
        authorProfileImageUrl: author?.profileImageUrl || null,
        title: selectedProducts.map((product) => product.name).join(" + "),
        content:
          `${CONTENTS[index % CONTENTS.length]} ${config.label} 공개 상품 데이터 기준이에요.` +
          (barcodeText ? ` 바코드 ${barcodeText}.` : ""),
        priceMin: priceTotal,
        priceMax: priceTotal,
        categories: categoriesFor(selectedProducts, index),
        likes: 0,
        likeEvents: [],
        dislikes: 0,
        comments: [],
        reviews: [],
        calories: null,
        rating: 0,
        imageData: null,
        imageUrl: imageUrls[0] || null,
        imageDatas: [],
        imageUrls,
        details: {
          eatingSteps: ["사진 속 상품을 같이 담고, 필요하면 매장에서 바로 데워 즐겨요."],
          tips: ["신상·PB·행사 표시는 수집된 편의점 상품 데이터에 있는 경우에만 붙어요."],
          cautions: [],
          situationTags: labels,
          reviewPoints: ["맛 조합", "가격 대비 만족도", "재구매 의사"],
          prepTimeTag: postKey,
        },
        likedByMe: false,
        dislikedByMe: false,
        topFiveEnteredAt: null,
        topWorstEnteredAt: null,
        createdAt: new Date(now.getTime() - created * 65 * 1000),
        updatedAt: now,
      });
      created += 1;
    }
  }

  console.log(JSON.stringify({ created, skipped, target: STORE_CONFIGS.reduce((sum, config) => sum + config.count, 0) }, null, 2));
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await mongoose.disconnect().catch(() => {});
  });
