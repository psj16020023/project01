require("dotenv").config({ path: require("path").join(__dirname, ".env") });

const express = require("express");
const cors = require("cors");
const mongoose = require("mongoose");
const { MongoMemoryServer } = require("mongodb-memory-server");
const path = require("path");

const app = express();
const PORT = Number(process.env.PORT || 3000);
const MONGO_URI = process.env.MONGO_URI || "";

app.use(cors());
app.use(express.json({ limit: "15mb" }));

const commentSchema = new mongoose.Schema(
  {
    text: { type: String, required: true },
    createdAt: { type: Date, default: Date.now },
  },
  { _id: false }
);

const postSchema = new mongoose.Schema(
  {
    title: { type: String, default: "제목 없는 꿀조합" },
    content: { type: String, default: "" },
    priceMin: { type: Number, required: true },
    priceMax: { type: Number, required: true },
    categories: [{ type: String, required: true }],
    likes: { type: Number, default: 0 },
    comments: { type: [commentSchema], default: [] },
    imageData: { type: String, default: null },
    imageUrl: { type: String, default: null },
    likedByMe: { type: Boolean, default: false },
    topFiveEnteredAt: { type: Date, default: null },
  },
  { timestamps: true }
);

const productSchema = new mongoose.Schema(
  {
    barcode: { type: String, required: true, unique: true, index: true },
    officialName: { type: String, required: true },
    brand: { type: String, default: null },
    store: { type: String, default: null },
    aliases: { type: [String], default: [] },
    source: { type: String, required: true },
    raw: { type: mongoose.Schema.Types.Mixed, default: null },
    lastVerifiedAt: { type: Date, default: Date.now },
  },
  { timestamps: true }
);

const Post = mongoose.model("Post", postSchema);
const Product = mongoose.model("Product", productSchema);

const seedPosts = [
  {
    title: "딸기우유 프레첼 한입 조합",
    content: "차갑게 둔 딸기우유를 한 모금 마시고 프레첼을 바로 먹으면 단짠이 깔끔하게 이어져요. 야근 끝나고 당 떨어질 때 가장 만족도가 높았어요.",
    priceMin: 2900,
    priceMax: 3600,
    categories: ["달달", "짭잘"],
    imageUrl: "https://images.unsplash.com/photo-1542826438-bd32f43d626f?auto=format&fit=crop&w=1200&q=80",
    likes: 31,
    comments: [{ text: "이거 시험기간에 진짜 좋아요." }, { text: "프레첼 대신 치즈크래커 넣어도 맛있어요." }],
    createdAt: new Date("2026-05-09T00:10:00.000Z"),
    updatedAt: new Date("2026-05-09T00:10:00.000Z"),
  },
  {
    title: "불닭삼각김밥 + 쿨피스 리셋 조합",
    content: "매운맛이 확 올라온 다음 쿨피스로 바로 식히면 중독성이 커져요. 스트레스 풀고 싶을 때 추천하는 가장 기본적인 편의점 꿀조합이에요.",
    priceMin: 2500,
    priceMax: 3300,
    categories: ["매콤"],
    imageUrl: "https://images.unsplash.com/photo-1515003197210-e0cd71810b5f?auto=format&fit=crop&w=1200&q=80",
    likes: 54,
    comments: [{ text: "맵찔이도 쿨피스 있으면 가능해요." }, { text: "전자레인지 20초 더 돌리면 더 맛있어요." }],
    createdAt: new Date("2026-05-08T23:42:00.000Z"),
    updatedAt: new Date("2026-05-08T23:42:00.000Z"),
  },
  {
    title: "요거트 + 컵과일 상큼 디저트",
    content: "달지 않은 그릭요거트에 컵과일을 올려 먹으면 포만감도 있고 후식 느낌도 좋아요. 아침 대용으로도 깔끔해서 자주 사 먹게 돼요.",
    priceMin: 4300,
    priceMax: 5200,
    categories: ["신", "건강"],
    imageUrl: "https://images.unsplash.com/photo-1488477181946-6428a0291777?auto=format&fit=crop&w=1200&q=80",
    likes: 47,
    comments: [{ text: "출근길 조합으로 저장했어요." }],
    createdAt: new Date("2026-05-08T11:18:00.000Z"),
    updatedAt: new Date("2026-05-08T11:18:00.000Z"),
  },
  {
    title: "참치마요 김밥 + 청양마요 소스",
    content: "느끼할 수 있는 참치마요에 청양마요를 더하면 확실하게 감칠맛이 살아나요. 매콤한데 과하지 않아서 입문 조합으로 좋아요.",
    priceMin: 3200,
    priceMax: 4100,
    categories: ["매콤", "짭잘"],
    imageUrl: "https://images.unsplash.com/photo-1553621042-f6e147245754?auto=format&fit=crop&w=1200&q=80",
    likes: 29,
    comments: [{ text: "소스 반만 넣어도 충분했어요." }],
    createdAt: new Date("2026-05-08T09:55:00.000Z"),
    updatedAt: new Date("2026-05-08T09:55:00.000Z"),
  },
  {
    title: "얼음컵 아메리카노 + 초코바삭롤",
    content: "씁쓸한 커피에 바삭한 초코롤이 붙으면 카페 대신 편의점으로 바로 향하게 돼요. 점심 뒤 졸릴 때 제일 무난하고 만족감 높은 조합입니다.",
    priceMin: 3800,
    priceMax: 4700,
    categories: ["달달"],
    imageUrl: "https://images.unsplash.com/photo-1509042239860-f550ce710b93?auto=format&fit=crop&w=1200&q=80",
    likes: 63,
    comments: [{ text: "이건 거의 국룰 조합이네요." }],
    createdAt: new Date("2026-05-08T04:02:00.000Z"),
    updatedAt: new Date("2026-05-08T04:02:00.000Z"),
  },
  {
    title: "닭가슴살볼 + 구운계란 든든 조합",
    content: "간단히 단백질 챙기고 싶은 날에 제일 실속 있어요. 소스가 강하지 않아서 질리지 않고, 운동 전후 간식으로도 부담이 적어요.",
    priceMin: 4200,
    priceMax: 5600,
    categories: ["건강", "짭잘"],
    imageUrl: "https://images.unsplash.com/photo-1512621776951-a57141f2eefd?auto=format&fit=crop&w=1200&q=80",
    likes: 22,
    comments: [{ text: "운동 끝나고 자주 먹는 조합이에요." }],
    createdAt: new Date("2026-05-08T00:20:00.000Z"),
    updatedAt: new Date("2026-05-08T00:20:00.000Z"),
  },
  {
    title: "레몬탄산수 + 새우칩 상큼짭짤",
    content: "느끼하지 않게 계속 손이 가는 조합이에요. 탄산이 입안을 정리해줘서 영화 볼 때 오래 먹기 좋고, 생각보다 질리지 않아요.",
    priceMin: 2600,
    priceMax: 3400,
    categories: ["신", "짭잘"],
    imageUrl: "https://images.unsplash.com/photo-1513558161293-cdaf765ed2fd?auto=format&fit=crop&w=1200&q=80",
    likes: 41,
    comments: [{ text: "맥주 느낌 대신 가볍게 즐기기 좋네요." }],
    createdAt: new Date("2026-05-07T13:11:00.000Z"),
    updatedAt: new Date("2026-05-07T13:11:00.000Z"),
  },
  {
    title: "쫀득빵 + 바닐라우유 야식 조합",
    content: "폭신한 빵에 차가운 우유를 곁들이면 늦은 밤에 기분 좋게 마무리되는 조합이에요. 너무 자극적이지 않아서 야식으로 무난해요.",
    priceMin: 3000,
    priceMax: 3900,
    categories: ["달달"],
    imageUrl: "https://images.unsplash.com/photo-1509440159596-0249088772ff?auto=format&fit=crop&w=1200&q=80",
    likes: 35,
    comments: [{ text: "전자레인지 10초 돌리면 더 좋아요." }],
    createdAt: new Date("2026-05-07T10:08:00.000Z"),
    updatedAt: new Date("2026-05-07T10:08:00.000Z"),
  },
];

function serializePost(post) {
  return {
    id: post._id.toString(),
    title: post.title,
    content: post.content,
    priceMin: post.priceMin,
    priceMax: post.priceMax,
    categories: post.categories,
    likes: post.likes,
    comments: post.comments.map((comment) => ({ text: comment.text, createdAt: comment.createdAt })),
    createdAt: post.createdAt,
    imageData: post.imageData,
    imageUrl: post.imageUrl,
    likedByMe: post.likedByMe,
    topFiveEnteredAt: post.topFiveEnteredAt,
  };
}

function serializeProduct(product, { cached }) {
  return {
    barcode: product.barcode,
    officialName: product.officialName,
    brand: product.brand,
    store: product.store,
    aliases: product.aliases,
    source: product.source,
    cached,
    lastVerifiedAt: product.lastVerifiedAt,
  };
}

function normalizeBarcode(input) {
  return String(input || "").replace(/[^0-9A-Za-z]/g, "");
}

function inferStore(product) {
  const sourceText = [
    product.stores,
    ...(product.stores_tags || []),
    ...(product.brands_tags || []),
    ...(product.categories_tags || []),
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();

  if (sourceText.includes("cu")) return "CU";
  if (sourceText.includes("gs25")) return "GS25";
  if (sourceText.includes("7-eleven") || sourceText.includes("seven eleven") || sourceText.includes("세븐일레븐")) {
    return "세븐일레븐";
  }
  if (sourceText.includes("emart24") || sourceText.includes("이마트24")) return "이마트24";
  return null;
}

async function fetchProductFromOpenFoodFacts(barcode) {
  const response = await fetch(`https://world.openfoodfacts.org/api/v2/product/${barcode}.json`, {
    headers: {
      "User-Agent": "PyeonPick/1.0 (barcode lookup for convenience food app)",
    },
    signal: AbortSignal.timeout(7000),
  });

  if (!response.ok) {
    throw new Error(`Open Food Facts lookup failed with status ${response.status}`);
  }

  const data = await response.json();
  const product = data.product;
  const officialName =
    product?.product_name_ko ||
    product?.product_name ||
    product?.generic_name_ko ||
    product?.generic_name ||
    "";

  if (!officialName) {
    return null;
  }

  const brand = product?.brands ? String(product.brands).split(",")[0].trim() : null;
  const store = inferStore(product);

  return {
    barcode,
    officialName: officialName.trim(),
    brand: brand || null,
    store,
    aliases: [product?.abbreviated_product_name, product?.product_name_en].filter(Boolean).map((item) => String(item).trim()),
    source: "open-food-facts",
    raw: product,
    lastVerifiedAt: new Date(),
  };
}

async function refreshTopFiveBadges() {
  const ranked = await Post.find({}).sort({ likes: -1, createdAt: -1 }).limit(5);
  const ids = new Set(ranked.map((post) => post._id.toString()));
  const now = new Date();
  const posts = await Post.find({});

  await Promise.all(
    posts.map(async (post) => {
      if (ids.has(post._id.toString()) && !post.topFiveEnteredAt) {
        post.topFiveEnteredAt = now;
        await post.save();
      }
    })
  );
}

async function seedIfNeeded() {
  if ((await Post.countDocuments()) > 0) return;
  await Post.insertMany(seedPosts);
  await refreshTopFiveBadges();
}

app.get("/api/posts", async (req, res) => {
  const { query = "", minPrice, maxPrice, sort = "latest" } = req.query;
  const filters = {};

  if (query) {
    if (String(query).startsWith("#")) {
      filters.categories = { $regex: String(query).slice(1), $options: "i" };
    } else {
      filters.title = { $regex: String(query), $options: "i" };
    }
  }

  if (minPrice || maxPrice) {
    filters.$and = [];
    if (minPrice) filters.$and.push({ priceMax: { $gte: Number(minPrice) } });
    if (maxPrice) filters.$and.push({ priceMin: { $lte: Number(maxPrice) } });
    if (filters.$and.length === 0) delete filters.$and;
  }

  const sortOption = sort === "popular" ? { likes: -1, createdAt: -1 } : { createdAt: -1 };
  const posts = await Post.find(filters).sort(sortOption);
  res.json({ posts: posts.map(serializePost) });
});

app.post("/api/posts", async (req, res) => {
  const { title, content, priceMin, priceMax, categories, imageData, imageUrl } = req.body;
  const hasImage = Boolean(imageData);
  const hasText = Boolean(title && content);

  if (!hasImage && !hasText) {
    return res.status(400).json({ message: "사진 또는 제목과 내용을 입력해야 합니다." });
  }
  if (!priceMin || !priceMax || Number(priceMin) <= 0 || Number(priceMax) < Number(priceMin)) {
    return res.status(400).json({ message: "가격 범위를 확인해 주세요." });
  }
  if (!Array.isArray(categories) || categories.length === 0) {
    return res.status(400).json({ message: "카테고리를 하나 이상 입력해 주세요." });
  }

  const post = await Post.create({
    title: title || "제목 없는 꿀조합",
    content: content || "",
    priceMin: Number(priceMin),
    priceMax: Number(priceMax),
    categories,
    imageData: imageData || null,
    imageUrl: imageUrl || null,
  });

  await refreshTopFiveBadges();
  res.status(201).json({ post: serializePost(post) });
});

app.post("/api/posts/:id/like", async (req, res) => {
  const post = await Post.findById(req.params.id);
  if (!post) return res.status(404).json({ message: "게시글을 찾을 수 없습니다." });

  if (post.likedByMe) {
    post.likes = Math.max(0, post.likes - 1);
    post.likedByMe = false;
  } else {
    post.likes += 1;
    post.likedByMe = true;
  }

  await post.save();
  await refreshTopFiveBadges();
  res.json({ post: serializePost(post) });
});

app.post("/api/posts/:id/comments", async (req, res) => {
  const { text } = req.body;
  if (!text || !String(text).trim()) {
    return res.status(400).json({ message: "댓글 내용을 입력해 주세요." });
  }

  const post = await Post.findById(req.params.id);
  if (!post) return res.status(404).json({ message: "게시글을 찾을 수 없습니다." });

  post.comments.push({ text: String(text).trim() });
  await post.save();
  res.json({ post: serializePost(post) });
});

app.get("/api/products/lookup/:barcode", async (req, res) => {
  const barcode = normalizeBarcode(req.params.barcode);
  if (!barcode) {
    return res.status(400).json({ message: "바코드가 비어 있습니다." });
  }

  const cached = await Product.findOne({ barcode });
  if (cached) {
    return res.json({ product: serializeProduct(cached, { cached: true }) });
  }

  try {
    const externalProduct = await fetchProductFromOpenFoodFacts(barcode);
    if (!externalProduct) {
      return res.status(404).json({ message: "외부 상품 정보에서 상품명을 찾지 못했습니다." });
    }

    const stored = await Product.findOneAndUpdate(
      { barcode },
      { $set: externalProduct },
      { new: true, upsert: true, setDefaultsOnInsert: true }
    );

    return res.json({ product: serializeProduct(stored, { cached: false }) });
  } catch (error) {
    console.error(`Product lookup failed for barcode ${barcode}:`, error);
    return res.status(502).json({ message: "외부 상품 조회에 실패했습니다." });
  }
});

const webBuildPath = path.join(__dirname, "..", "frontend", "pyeonpick_app", "build", "web");
app.use(express.static(webBuildPath));

app.get(/^(?!\/api).*/, (req, res) => {
  res.sendFile(path.join(webBuildPath, "index.html"));
});

async function start() {
  let mongoLabel = "in-memory MongoDB";

  if (MONGO_URI) {
    await mongoose.connect(MONGO_URI);
    mongoLabel = "external MongoDB";
  } else if (process.env.ALLOW_IN_MEMORY_MONGO === "true") {
    const mongoServer = await MongoMemoryServer.create();
    await mongoose.connect(mongoServer.getUri());
  } else {
    throw new Error("MONGO_URI is required. Add it to backend/.env to use your MongoDB account.");
  }

  await seedIfNeeded();

  app.listen(PORT, "0.0.0.0", () => {
    console.log(`PyeonPick full-stack server running at http://0.0.0.0:${PORT} using ${mongoLabel}`);
  });
}

start().catch((error) => {
  console.error(error);
  process.exit(1);
});
