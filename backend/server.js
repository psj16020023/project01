require("dotenv").config({ path: require("path").join(__dirname, ".env") });

const express = require("express");
const cors = require("cors");
const mongoose = require("mongoose");
const { MongoMemoryServer } = require("mongodb-memory-server");
const path = require("path");
const crypto = require("crypto");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");

const app = express();
const PORT = Number(process.env.PORT || 3000);
const MONGO_URI = process.env.MONGO_URI || "";
const JWT_SECRET = String(
  process.env.JWT_SECRET || "pyeonpick-local-development-secret"
);
const usesDefaultJwtSecret = !process.env.JWT_SECRET;

app.use(cors());
app.use(express.json({ limit: "15mb" }));

function isValidObjectId(value) {
  return mongoose.Types.ObjectId.isValid(String(value || ""));
}

function findUserByIdOrNull(id) {
  if (!isValidObjectId(id)) return null;
  return User.findById(String(id));
}

function findUserByIdLeanOrNull(id) {
  if (!isValidObjectId(id)) return null;
  return User.findById(String(id)).lean();
}

function proxiedImagePath(imageUrl) {
  const raw = String(imageUrl || "").trim();
  if (!/^https?:\/\//i.test(raw)) return raw;
  return `/api/image-proxy?url=${encodeURIComponent(raw)}`;
}

const commentSchema = new mongoose.Schema(
  {
    authorId: { type: String, default: "" },
    authorNickname: { type: String, default: "익명" },
    authorProfileImageUrl: { type: String, default: null },
    text: { type: String, required: true },
    createdAt: { type: Date, default: Date.now },
  },
  { _id: false }
);

const postReviewSchema = new mongoose.Schema(
  {
    id: { type: String, required: true },
    authorId: { type: String, default: "" },
    authorNickname: { type: String, default: "익명" },
    text: { type: String, default: "" },
    rating: { type: Number, min: 1, max: 5, default: 3 },
    tags: { type: [String], default: [] },
    sweet: { type: Number, min: 1, max: 5, default: 1 },
    salty: { type: Number, min: 1, max: 5, default: 1 },
    spicy: { type: Number, min: 1, max: 5, default: 1 },
    sour: { type: Number, min: 1, max: 5, default: 1 },
    caution: { type: String, default: "" },
    createdAt: { type: Date, default: Date.now },
  },
  { _id: false }
);

const postDetailsSchema = new mongoose.Schema(
  {
    eatingSteps: { type: [String], default: [] },
    tips: { type: [String], default: [] },
    cautions: { type: [String], default: [] },
    situationTags: { type: [String], default: [] },
    reviewPoints: { type: [String], default: [] },
    prepTimeTag: { type: String, default: "" },
  },
  { _id: false }
);

const botSetupSchema = new mongoose.Schema(
  {
    age: { type: Number, default: 20 },
    gender: { type: String, enum: ["남자", "여자"], default: null },
    tasteRatings: { type: Map, of: Number, default: {} },
    priorityValues: { type: [String], default: [] },
    favoriteTastes: { type: [String], default: [] },
    reasons: { type: [String], default: [] },
  },
  { _id: false }
);

const botMessageSchema = new mongoose.Schema(
  {
    role: { type: String, default: "assistant" },
    text: { type: String, default: "" },
    createdAt: { type: Date, default: Date.now },
    recommendedPostIds: { type: [String], default: [] },
    resolvedBudget: { type: Number, default: null },
    minimumPrice: { type: Number, default: null },
    contextPrompt: { type: String, default: null },
    useAgeCalorieGuide: { type: Boolean, default: null },
    pendingClarification: { type: String, default: null },
    pendingAmount: { type: Number, default: null },
  },
  { _id: false }
);

const botConversationSchema = new mongoose.Schema(
  {
    id: { type: String, required: true },
    title: { type: String, default: "대화" },
    messages: { type: [botMessageSchema], default: [] },
    updatedAt: { type: Date, default: Date.now },
  },
  { _id: false }
);

const profileVisibilitySchema = new mongoose.Schema(
  {
    username: { type: Boolean, default: false },
    likes: { type: Boolean, default: true },
    dislikes: { type: Boolean, default: false },
    saved: { type: Boolean, default: false },
    myPosts: { type: Boolean, default: true },
    picks: { type: Boolean, default: true },
    pickedBy: { type: Boolean, default: true },
  },
  { _id: false }
);

const productSourceSchema = new mongoose.Schema(
  {
    source: { type: String, required: true },
    officialName: { type: String, default: null },
    brand: { type: String, default: null },
    manufacturer: { type: String, default: null },
    seller: { type: String, default: null },
    store: { type: String, default: null },
    capacity: { type: String, default: null },
    price: { type: Number, default: null },
    calories: { type: Number, default: null },
    categories: { type: [String], default: [] },
    aliases: { type: [String], default: [] },
    imageUrl: { type: String, default: null },
    metaImageUrl: { type: String, default: null },
    checkedAt: { type: Date, default: Date.now },
    raw: { type: mongoose.Schema.Types.Mixed, default: null },
  },
  { _id: false }
);

const likeEventSchema = new mongoose.Schema(
  {
    userId: { type: String, required: true },
    createdAt: { type: Date, default: Date.now },
  },
  { _id: false }
);

const postSchema = new mongoose.Schema(
  {
    authorId: { type: String, required: true },
    authorNickname: { type: String, required: true },
    authorProfileImageUrl: { type: String, default: null },
    title: { type: String, default: "제목 없는 꿀조합" },
    content: { type: String, default: "" },
    priceMin: { type: Number, required: true },
    priceMax: { type: Number, required: true },
    categories: [{ type: String, required: true }],
    likes: { type: Number, default: 0 },
    likeEvents: { type: [likeEventSchema], default: [] },
    dislikes: { type: Number, default: 0 },
    comments: { type: [commentSchema], default: [] },
    reviews: { type: [postReviewSchema], default: [] },
    calories: { type: Number, default: null },
    rating: { type: Number, min: 0, max: 5, default: 0 },
    imageData: { type: String, default: null },
    imageUrl: { type: String, default: null },
    imageDatas: { type: [String], default: [] },
    imageUrls: { type: [String], default: [] },
    details: { type: postDetailsSchema, default: () => ({}) },
    likedByMe: { type: Boolean, default: false },
    dislikedByMe: { type: Boolean, default: false },
    topFiveEnteredAt: { type: Date, default: null },
    topWorstEnteredAt: { type: Date, default: null },
  },
  { timestamps: true }
);

const productSchema = new mongoose.Schema(
  {
    barcode: { type: String, required: true, unique: true, index: true },
    officialName: { type: String, required: true },
    normalizedName: { type: String, default: null, index: true },
    brand: { type: String, default: null },
    manufacturer: { type: String, default: null },
    seller: { type: String, default: null },
    store: { type: String, default: null },
    capacity: { type: String, default: null },
    price: { type: Number, default: null },
    calories: { type: Number, default: null },
    aliases: { type: [String], default: [] },
    categories: { type: [String], default: [] },
    images: {
      product: { type: String, default: null },
      meta: { type: String, default: null },
    },
    searchTokens: { type: [String], default: [] },
    source: { type: String, required: true },
    sources: { type: [productSourceSchema], default: [] },
    verificationStatus: { type: String, default: "auto-imported" },
    lookupCount: { type: Number, default: 1 },
    raw: { type: mongoose.Schema.Types.Mixed, default: null },
    lastVerifiedAt: { type: Date, default: Date.now },
  },
  { timestamps: true }
);

productSchema.index({ officialName: "text", aliases: "text", brand: "text", manufacturer: "text", seller: "text" });

const productLookupMissSchema = new mongoose.Schema(
  {
    barcode: { type: String, required: true, unique: true, index: true },
    failureCount: { type: Number, default: 1 },
    checkedSources: { type: [String], default: [] },
    lastErrorMessages: { type: [String], default: [] },
    firstSeenAt: { type: Date, default: Date.now },
    lastTriedAt: { type: Date, default: Date.now },
  },
  { timestamps: true }
);

const cuProductSchema = new mongoose.Schema(
  {
    id: { type: String, required: true, unique: true, index: true },
    store: { type: String, default: "CU", index: true },
    productId: { type: String, required: true, unique: true, index: true },
    name: { type: String, required: true, index: true },
    normalizedName: { type: String, default: null, index: true },
    price: { type: String, default: "" },
    imageUrl: { type: String, default: null },
    barcode: { type: String, default: null, index: true },
    isNewFlag: { type: Boolean, default: false },
    isNewByDiff: { type: Boolean, default: false },
    isPb: { type: Boolean, default: false },
    categoryCode: { type: String, default: null },
    firstSeenAt: { type: Date, default: Date.now },
    lastSeenAt: { type: Date, default: Date.now },
    lastCrawledAt: { type: Date, default: Date.now },
    rawText: { type: String, default: "" },
  },
  { timestamps: true }
);

cuProductSchema.index({ name: "text", normalizedName: "text", barcode: "text" });

const convenienceProductSchema = new mongoose.Schema(
  {
    id: { type: String, required: true, unique: true, index: true },
    store: { type: String, required: true, index: true },
    productId: { type: String, default: null, index: true },
    name: { type: String, required: true, index: true },
    normalizedName: { type: String, default: null, index: true },
    price: { type: String, default: "" },
    imageUrl: { type: String, default: null },
    barcode: { type: String, default: null, index: true },
    isNewFlag: { type: Boolean, default: false },
    isNewByDiff: { type: Boolean, default: false },
    isPb: { type: Boolean, default: false },
    tags: { type: [String], default: [] },
    sourcePage: { type: String, default: "" },
    firstSeenAt: { type: Date, default: Date.now },
    lastSeenAt: { type: Date, default: Date.now },
    lastCrawledAt: { type: Date, default: Date.now },
    rawText: { type: String, default: "" },
  },
  { timestamps: true }
);

convenienceProductSchema.index({ store: 1, normalizedName: 1 });
convenienceProductSchema.index({ name: "text", normalizedName: "text", barcode: "text", tags: "text" });

const userSchema = new mongoose.Schema(
  {
    username: { type: String, required: true, unique: true, index: true },
    nickname: { type: String, required: true, unique: true, index: true },
    passwordHash: { type: String, required: true },
    profileImageUrl: { type: String, default: null },
    botSetup: { type: botSetupSchema, default: null },
    memoryNotes: { type: [String], default: [] },
    botMessages: { type: [botMessageSchema], default: [] },
    archivedConversations: { type: [botConversationSchema], default: [] },
    likedPostIds: { type: [String], default: [] },
    dislikedPostIds: { type: [String], default: [] },
    savedPostIds: { type: [String], default: [] },
    pickedAuthorIds: { type: [String], default: [] },
    battleState: { type: mongoose.Schema.Types.Mixed, default: () => ({}) },
    profilePublic: { type: Boolean, default: true },
    profileVisibility: { type: profileVisibilitySchema, default: () => ({}) },
  },
  { timestamps: true }
);

const Post = mongoose.model("Post", postSchema);
const Product = mongoose.model("Product", productSchema);
const ProductLookupMiss = mongoose.model("ProductLookupMiss", productLookupMissSchema);
const CuProduct = mongoose.model("CuProduct", cuProductSchema);
const ConvenienceProduct = mongoose.model("ConvenienceProduct", convenienceProductSchema);
const User = mongoose.model("User", userSchema);

const seedUserIds = {
  ai1: new mongoose.Types.ObjectId("683ab41f0a22b15a8a101001"),
  ai2: new mongoose.Types.ObjectId("683ab41f0a22b15a8a101002"),
  ai3: new mongoose.Types.ObjectId("683ab41f0a22b15a8a101003"),
  ai4: new mongoose.Types.ObjectId("683ab41f0a22b15a8a101004"),
  ai5: new mongoose.Types.ObjectId("683ab41f0a22b15a8a101005"),
  ai6: new mongoose.Types.ObjectId("683ab41f0a22b15a8a101006"),
  ai7: new mongoose.Types.ObjectId("683ab41f0a22b15a8a101007"),
};

const seedUsers = [
  {
    _id: seedUserIds.ai1,
    username: "ai1",
    nickname: "민지의 편픽",
    passwordHash: hashPassword("ai1"),
    profileImageUrl: "https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=300&q=80",
    profilePublic: true,
    profileVisibility: { username: true, likes: true, dislikes: false, saved: false, myPosts: true, picks: true, pickedBy: true },
  },
  {
    _id: seedUserIds.ai2,
    username: "ai2",
    nickname: "야식연구소",
    passwordHash: hashPassword("ai2"),
    profileImageUrl: "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=300&q=80",
    profilePublic: true,
    profileVisibility: { username: false, likes: false, dislikes: false, saved: false, myPosts: true, picks: true, pickedBy: true },
  },
  {
    _id: seedUserIds.ai3,
    username: "ai3",
    nickname: "초코라면",
    passwordHash: hashPassword("ai3"),
    profileImageUrl: "https://images.unsplash.com/photo-1438761681033-6461ffad8d80?auto=format&fit=crop&w=300&q=80",
    profilePublic: false,
    profileVisibility: { username: false, likes: false, dislikes: false, saved: false, myPosts: true, picks: false, pickedBy: false },
  },
  {
    _id: seedUserIds.ai4,
    username: "ai4",
    nickname: "신상편돌이",
    passwordHash: hashPassword("ai4"),
    profileImageUrl: "https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=300&q=80",
    profilePublic: true,
    profileVisibility: { username: true, likes: false, dislikes: false, saved: false, myPosts: true, picks: true, pickedBy: true },
  },
  {
    _id: seedUserIds.ai5,
    username: "ai5",
    nickname: "가성비탐험가",
    passwordHash: hashPassword("ai5"),
    profileImageUrl: "https://images.unsplash.com/photo-1488426862026-3ee34a7d66df?auto=format&fit=crop&w=300&q=80",
    profilePublic: true,
    profileVisibility: { username: false, likes: true, dislikes: true, saved: false, myPosts: true, picks: true, pickedBy: true },
  },
  {
    _id: seedUserIds.ai6,
    username: "ai6",
    nickname: "편식가이드",
    passwordHash: hashPassword("ai6"),
    profileImageUrl: "https://images.unsplash.com/photo-1544005313-94ddf0286df2?auto=format&fit=crop&w=300&q=80",
    profilePublic: false,
    profileVisibility: { username: false, likes: false, dislikes: false, saved: false, myPosts: true, picks: false, pickedBy: false },
  },
  {
    _id: seedUserIds.ai7,
    username: "ai7",
    nickname: "매콤주의보",
    passwordHash: hashPassword("ai7"),
    profileImageUrl: "https://images.unsplash.com/photo-1521119989659-a83eee488004?auto=format&fit=crop&w=300&q=80",
    profilePublic: true,
    profileVisibility: { username: true, likes: false, dislikes: false, saved: false, myPosts: true, picks: true, pickedBy: true },
  },
];

const seedPosts = [
  {
    authorId: seedUserIds.ai1.toString(),
    authorNickname: seedUsers[0].nickname,
    authorProfileImageUrl: seedUsers[0].profileImageUrl,
    title: "딸기우유 + 허니버터칩 야근 위로 조합",
    content: "달고 짭짤한 조합인데 생각보다 질리지 않아요. 단 거 당길 때 가장 먼저 떠오르는 기본 조합이에요.",
    priceMin: 3800,
    priceMax: 3800,
    categories: ["달달", "짭짤", "또 먹고 싶어요", "야식 추천"],
    imageUrls: [
      "https://images.unsplash.com/photo-1551024601-bec78aea704b?auto=format&fit=crop&w=900&q=80",
      "https://images.unsplash.com/photo-1519864600265-abb23847ef2c?auto=format&fit=crop&w=900&q=80",
    ],
    likes: 52,
    dislikes: 7,
    comments: [{ authorId: seedUserIds.ai4.toString(), authorNickname: seedUsers[3].nickname, text: "시험기간에 진짜 손이 가는 조합이에요." }],
    details: {
      eatingSteps: ["우유를 차갑게 마신 뒤 칩을 바로 집어 먹기"],
      tips: ["칩은 반 봉지만 먹어도 만족도가 높아요."],
      cautions: ["생각보다 달아요"],
      situationTags: ["야식 추천"],
      reviewPoints: ["😋 또 먹고 싶어요"],
    },
    topFiveEnteredAt: new Date("2026-05-11T12:00:00.000Z"),
    createdAt: new Date("2026-05-09T00:10:00.000Z"),
    updatedAt: new Date("2026-05-09T00:10:00.000Z"),
  },
  {
    authorId: seedUserIds.ai2.toString(),
    authorNickname: seedUsers[1].nickname,
    authorProfileImageUrl: seedUsers[1].profileImageUrl,
    title: "불닭 삼각김밥 + 쿨피스 진정 조합",
    content: "맵고 자극적인데 스트레스 풀리는 타입이에요. 쿨피스로 한 번 식혀주면 다시 들어갑니다.",
    priceMin: 3100,
    priceMax: 3100,
    categories: ["매콤", "기대 이상이에요", "야식 추천", "호불호"],
    imageUrls: [
      "https://images.unsplash.com/photo-1547592180-85f173990554?auto=format&fit=crop&w=900&q=80",
      "https://images.unsplash.com/photo-1515003197210-e0cd71810b5f?auto=format&fit=crop&w=900&q=80",
    ],
    likes: 70,
    dislikes: 16,
    comments: [{ authorId: seedUserIds.ai7.toString(), authorNickname: seedUsers[6].nickname, text: "맵찔이는 우유 추가 추천해요." }],
    details: {
      eatingSteps: ["삼김을 20초 데운 뒤 쿨피스와 번갈아 먹기"],
      tips: ["전자레인지 10초만 추가해도 훨씬 부드러워요."],
      cautions: ["생각보다 매워요"],
      situationTags: ["야식 추천", "공부할 때 추천"],
      reviewPoints: ["👍 기대 이상이에요"],
    },
    topFiveEnteredAt: new Date("2026-05-12T12:00:00.000Z"),
    topWorstEnteredAt: new Date("2026-05-18T12:00:00.000Z"),
    createdAt: new Date("2026-05-08T23:42:00.000Z"),
    updatedAt: new Date("2026-05-08T23:42:00.000Z"),
  },
  {
    authorId: seedUserIds.ai3.toString(),
    authorNickname: seedUsers[2].nickname,
    authorProfileImageUrl: seedUsers[2].profileImageUrl,
    title: "그릭요거트 + 컵과일 가벼운 출근 조합",
    content: "상큼해서 속이 편하고 포만감도 적당해요. 아침 대용으로 깔끔하게 먹기 좋아요.",
    priceMin: 4800,
    priceMax: 4800,
    categories: ["건강", "신", "맛있게 먹었어요", "등교길 추천"],
    imageUrls: [
      "https://images.unsplash.com/photo-1488477181946-6428a0291777?auto=format&fit=crop&w=900&q=80",
    ],
    likes: 33,
    dislikes: 3,
    comments: [{ authorId: seedUserIds.ai1.toString(), authorNickname: seedUsers[0].nickname, text: "가볍게 먹고 싶을 때 저장해두는 조합이에요." }],
    details: {
      eatingSteps: ["요거트에 과일을 바로 얹어 먹기"],
      tips: ["견과류 토핑이 있으면 식감이 더 좋아져요."],
      cautions: ["양이 적어요"],
      situationTags: ["등교길 추천", "다이어트 할 때 추천"],
      reviewPoints: ["💯 맛있게 먹었어요"],
    },
    topFiveEnteredAt: new Date("2026-05-10T10:30:00.000Z"),
    createdAt: new Date("2026-05-08T11:18:00.000Z"),
    updatedAt: new Date("2026-05-08T11:18:00.000Z"),
  },
  {
    authorId: seedUserIds.ai4.toString(),
    authorNickname: seedUsers[3].nickname,
    authorProfileImageUrl: seedUsers[3].profileImageUrl,
    title: "초코우유 + 촉촉한 카스테라 등교길 조합",
    content: "등교길에 무난하게 배 채우기 좋고 실패가 없어요.",
    priceMin: 3500,
    priceMax: 3500,
    categories: ["달달", "만족스러워요", "등교길 추천"],
    imageUrls: [
      "https://images.unsplash.com/photo-1519864600265-abb23847ef2c?auto=format&fit=crop&w=900&q=80",
      "https://images.unsplash.com/photo-1509440159596-0249088772ff?auto=format&fit=crop&w=900&q=80",
    ],
    likes: 28,
    dislikes: 4,
    details: {
      eatingSteps: ["우유를 먼저 한 모금 마시고 빵을 찢어 먹기"],
      tips: ["카스테라는 살짝 차가워도 맛있어요."],
      cautions: ["생각보다 달아요"],
      situationTags: ["등교길 추천", "아침 대용"],
      reviewPoints: ["🥰 만족스러워요"],
    },
    createdAt: new Date("2026-05-12T07:44:00.000Z"),
    updatedAt: new Date("2026-05-12T07:44:00.000Z"),
  },
  {
    authorId: seedUserIds.ai5.toString(),
    authorNickname: seedUsers[4].nickname,
    authorProfileImageUrl: seedUsers[4].profileImageUrl,
    title: "참치마요 삼각김밥 + 컵된장국 든든 조합",
    content: "가격 대비 만족도가 좋아서 점심 대용으로 자주 먹게 돼요.",
    priceMin: 3200,
    priceMax: 3200,
    categories: ["짭짤", "가격 대비 만족", "점심 대용"],
    imageUrls: ["https://images.unsplash.com/photo-1574484284002-952d92456975?auto=format&fit=crop&w=900&q=80"],
    likes: 41,
    dislikes: 5,
    details: {
      eatingSteps: ["삼김과 컵국을 같이 데워서 먹기"],
      tips: ["된장국은 물을 정량보다 살짝 적게 넣어도 좋아요."],
      cautions: ["향이 강해요"],
      situationTags: ["점심 대용", "공부할 때 추천"],
      reviewPoints: ["👍 가격 대비 만족"],
    },
    createdAt: new Date("2026-05-12T12:18:00.000Z"),
    updatedAt: new Date("2026-05-12T12:18:00.000Z"),
  },
  {
    authorId: seedUserIds.ai6.toString(),
    authorNickname: seedUsers[5].nickname,
    authorProfileImageUrl: seedUsers[5].profileImageUrl,
    title: "반숙란 2개 + 프로틴우유 운동 후 조합",
    content: "담백해서 질리지 않고 운동 끝나고 가볍게 보충하기 좋았어요.",
    priceMin: 4600,
    priceMax: 4600,
    categories: ["건강", "든든하게 먹었어요", "운동 후 추천"],
    imageUrls: ["https://images.unsplash.com/photo-1569288063643-5d29ad0e570e?auto=format&fit=crop&w=900&q=80"],
    likes: 22,
    dislikes: 2,
    details: {
      eatingSteps: ["반숙란을 먼저 먹고 우유로 마무리하기"],
      tips: ["얼음컵이 있으면 프로틴우유가 더 맛있어요."],
      cautions: ["향이 강해요"],
      situationTags: ["운동 후 추천", "다이어트 할 때 추천"],
      reviewPoints: ["🍚 든든하게 먹었어요"],
    },
    createdAt: new Date("2026-05-13T20:11:00.000Z"),
    updatedAt: new Date("2026-05-13T20:11:00.000Z"),
  },
  {
    authorId: seedUserIds.ai7.toString(),
    authorNickname: seedUsers[6].nickname,
    authorProfileImageUrl: seedUsers[6].profileImageUrl,
    title: "마라 컵라면 + 치즈스틱 호불호 조합",
    content: "매운맛은 좋지만 느끼함이 같이 올라와서 호불호가 꽤 있어요.",
    priceMin: 5200,
    priceMax: 5200,
    categories: ["매콤", "호불호 있어요", "야식 추천"],
    imageUrls: [
      "https://images.unsplash.com/photo-1617093727343-374698b1b08d?auto=format&fit=crop&w=900&q=80",
      "https://images.unsplash.com/photo-1569718212165-3a8278d5f624?auto=format&fit=crop&w=900&q=80",
    ],
    likes: 18,
    dislikes: 23,
    details: {
      eatingSteps: ["라면에 치즈스틱을 반만 잘라 같이 먹기"],
      tips: ["치즈스틱은 전자레인지 10초만 데워도 충분해요."],
      cautions: ["호불호 있어요", "생각보다 매워요"],
      situationTags: ["야식 추천"],
      reviewPoints: ["⭐ 후회 없는 선택"],
    },
    topWorstEnteredAt: new Date("2026-05-16T21:00:00.000Z"),
    createdAt: new Date("2026-05-14T22:08:00.000Z"),
    updatedAt: new Date("2026-05-14T22:08:00.000Z"),
  },
  {
    authorId: seedUserIds.ai1.toString(),
    authorNickname: seedUsers[0].nickname,
    authorProfileImageUrl: seedUsers[0].profileImageUrl,
    title: "바나나우유 + 초코칩쿠키 피크닉 조합",
    content: "가볍고 실패 없는 달달 조합이라 밖에서 먹기 좋아요.",
    priceMin: 3400,
    priceMax: 3400,
    categories: ["달달", "추천하고 싶어요", "피크닉 추천"],
    imageUrls: [
      "https://images.unsplash.com/photo-1519864600265-abb23847ef2c?auto=format&fit=crop&w=900&q=80",
      "https://images.unsplash.com/photo-1499636136210-6f4ee915583e?auto=format&fit=crop&w=900&q=80",
    ],
    likes: 39,
    dislikes: 1,
    details: {
      eatingSteps: ["우유 한 모금 뒤 쿠키 한입"],
      tips: ["날 더울 때는 얼음컵과 같이 사면 좋아요."],
      cautions: ["생각보다 달아요"],
      situationTags: ["피크닉 추천", "간식 추천"],
      reviewPoints: ["👏 추천하고 싶어요"],
    },
    createdAt: new Date("2026-05-15T16:42:00.000Z"),
    updatedAt: new Date("2026-05-15T16:42:00.000Z"),
  },
  {
    authorId: seedUserIds.ai2.toString(),
    authorNickname: seedUsers[1].nickname,
    authorProfileImageUrl: seedUsers[1].profileImageUrl,
    title: "김치볶음참치 삼김 + 컵라면 해장 조합",
    content: "국물까지 먹으면 든든한데 나트륨이 꽤 높아서 자주는 비추천이에요.",
    priceMin: 4100,
    priceMax: 4100,
    categories: ["짭짤", "한 끼로 딱이에요", "점심 대용"],
    imageUrls: [
      "https://images.unsplash.com/photo-1574484284002-952d92456975?auto=format&fit=crop&w=900&q=80",
      "https://images.unsplash.com/photo-1607301405390-d831c242f59b?auto=format&fit=crop&w=900&q=80",
    ],
    likes: 44,
    dislikes: 12,
    details: {
      eatingSteps: ["라면 3분 후 삼김 반 넣어서 같이 먹기"],
      tips: ["김치맛 라면보다 순한 라면이 더 어울려요."],
      cautions: ["생각보다 짜요"],
      situationTags: ["점심 대용", "야식 추천"],
      reviewPoints: ["🍽️ 한 끼로 딱이에요"],
    },
    topFiveEnteredAt: new Date("2026-05-17T12:00:00.000Z"),
    createdAt: new Date("2026-05-16T12:22:00.000Z"),
    updatedAt: new Date("2026-05-16T12:22:00.000Z"),
  },
  {
    authorId: seedUserIds.ai4.toString(),
    authorNickname: seedUsers[3].nickname,
    authorProfileImageUrl: seedUsers[3].profileImageUrl,
    title: "모짜렐라 핫도그 + 요구르트 반전 조합",
    content: "생각보다 어울린다는 반응과 이상하다는 반응이 동시에 나왔어요.",
    priceMin: 3900,
    priceMax: 3900,
    categories: ["호불호 있어요", "만족스러워요", "간식 추천", "호불호"],
    imageUrls: [
      "https://images.unsplash.com/photo-1551024601-bec78aea704b?auto=format&fit=crop&w=900&q=80",
      "https://images.unsplash.com/photo-1488477181946-6428a0291777?auto=format&fit=crop&w=900&q=80",
    ],
    likes: 25,
    dislikes: 25,
    details: {
      eatingSteps: ["핫도그 한입 뒤 요구르트로 마무리"],
      tips: ["전자레인지 15초 추가하면 치즈가 잘 늘어나요."],
      cautions: ["호불호 있어요"],
      situationTags: ["간식 추천"],
      reviewPoints: ["🥰 만족스러워요"],
    },
    topFiveEnteredAt: new Date("2026-05-20T14:00:00.000Z"),
    topWorstEnteredAt: new Date("2026-05-20T14:00:00.000Z"),
    createdAt: new Date("2026-05-20T13:44:00.000Z"),
    updatedAt: new Date("2026-05-20T13:44:00.000Z"),
  },
  {
    authorId: seedUserIds.ai5.toString(),
    authorNickname: seedUsers[4].nickname,
    authorProfileImageUrl: seedUsers[4].profileImageUrl,
    title: "치즈볶이 + 사이다 스트레스 해소 조합",
    content: "달달하게 마무리되는 탄산 덕분에 맵기가 덜 부담스러워요.",
    priceMin: 4300,
    priceMax: 4300,
    categories: ["매콤", "또 먹고 싶어요", "야식 추천"],
    imageUrls: [
      "https://images.unsplash.com/photo-1515003197210-e0cd71810b5f?auto=format&fit=crop&w=900&q=80",
      "https://images.unsplash.com/photo-1629203851122-3726ecdf080e?auto=format&fit=crop&w=900&q=80",
    ],
    likes: 47,
    dislikes: 6,
    details: {
      eatingSteps: ["볶이를 먼저 먹고 탄산으로 입안을 정리하기"],
      tips: ["사이다는 얼음컵에 따르면 훨씬 시원해요."],
      cautions: ["생각보다 매워요"],
      situationTags: ["야식 추천"],
      reviewPoints: ["😋 또 먹고 싶어요"],
    },
    topFiveEnteredAt: new Date("2026-05-21T18:00:00.000Z"),
    createdAt: new Date("2026-05-21T17:20:00.000Z"),
    updatedAt: new Date("2026-05-21T17:20:00.000Z"),
  },
  {
    authorId: seedUserIds.ai6.toString(),
    authorNickname: seedUsers[5].nickname,
    authorProfileImageUrl: seedUsers[5].profileImageUrl,
    title: "곤약젤리 + 아몬드브리즈 가벼운 간식 조합",
    content: "달달한데 부담이 덜해서 출근 전에 챙기기 좋았어요.",
    priceMin: 4200,
    priceMax: 4200,
    categories: ["건강", "간식 추천", "만족스러워요"],
    imageUrls: [
      "https://images.unsplash.com/photo-1547592180-85f173990554?auto=format&fit=crop&w=900&q=80",
    ],
    likes: 26,
    dislikes: 2,
    details: {
      eatingSteps: ["젤리를 먼저 먹고 음료를 천천히 마시기"],
      tips: ["차갑게 먹어야 식감이 더 좋아요."],
      cautions: ["양이 적어요"],
      situationTags: ["등교길 추천", "간식 추천"],
      reviewPoints: ["🥰 만족스러워요"],
    },
    createdAt: new Date("2026-05-21T09:08:00.000Z"),
    updatedAt: new Date("2026-05-21T09:08:00.000Z"),
  },
  {
    authorId: seedUserIds.ai7.toString(),
    authorNickname: seedUsers[6].nickname,
    authorProfileImageUrl: seedUsers[6].profileImageUrl,
    title: "얼큰해장국 컵밥 + 반숙란 든든 조합",
    content: "한 끼로 꽤 든든한 편인데 국물 향이 강해서 호불호는 있어요.",
    priceMin: 5400,
    priceMax: 5400,
    categories: ["짭짤", "든든하게 먹었어요", "점심 대용"],
    imageUrls: [
      "https://images.unsplash.com/photo-1574484284002-952d92456975?auto=format&fit=crop&w=900&q=80",
    ],
    likes: 31,
    dislikes: 9,
    details: {
      eatingSteps: ["컵밥을 데운 뒤 반숙란을 올려 같이 먹기"],
      tips: ["국물은 절반만 넣어도 충분히 진해요."],
      cautions: ["향이 강해요"],
      situationTags: ["점심 대용", "공부할 때 추천"],
      reviewPoints: ["🍚 든든하게 먹었어요"],
    },
    createdAt: new Date("2026-05-21T13:05:00.000Z"),
    updatedAt: new Date("2026-05-21T13:05:00.000Z"),
  },
  {
    authorId: seedUserIds.ai1.toString(),
    authorNickname: seedUsers[0].nickname,
    authorProfileImageUrl: seedUsers[0].profileImageUrl,
    title: "말차라떼 + 초코샌드 쿠키 휴식 조합",
    content: "살짝 쌉싸름한 맛 덕분에 단맛이 과하게 느껴지지 않아요.",
    priceMin: 4700,
    priceMax: 4700,
    categories: ["달달", "간식 추천", "최애 메뉴 등극"],
    imageUrls: [
      "https://images.unsplash.com/photo-1499636136210-6f4ee915583e?auto=format&fit=crop&w=900&q=80",
      "https://images.unsplash.com/photo-1519864600265-abb23847ef2c?auto=format&fit=crop&w=900&q=80",
    ],
    likes: 53,
    dislikes: 4,
    details: {
      eatingSteps: ["쿠키를 한입 먹고 라떼로 마무리하기"],
      tips: ["라떼는 얼음이 살짝 녹았을 때가 더 부드러워요."],
      cautions: ["생각보다 달아요"],
      situationTags: ["간식 추천", "영화 보며 먹기 좋아요"],
      reviewPoints: ["❤️ 최애 메뉴 등극"],
    },
    topFiveEnteredAt: new Date("2026-05-22T11:00:00.000Z"),
    createdAt: new Date("2026-05-22T10:18:00.000Z"),
    updatedAt: new Date("2026-05-22T10:18:00.000Z"),
  },
  {
    authorId: seedUserIds.ai2.toString(),
    authorNickname: seedUsers[1].nickname,
    authorProfileImageUrl: seedUsers[1].profileImageUrl,
    title: "청양참치김밥 + 바나나우유 반전 조합",
    content: "맵고 달아서 은근 계속 먹게 되는데 호불호는 확실해요.",
    priceMin: 3900,
    priceMax: 3900,
    categories: ["호불호", "호불호 있어요", "간식 추천"],
    imageUrls: [
      "https://images.unsplash.com/photo-1574484284002-952d92456975?auto=format&fit=crop&w=900&q=80",
      "https://images.unsplash.com/photo-1519864600265-abb23847ef2c?auto=format&fit=crop&w=900&q=80",
    ],
    likes: 19,
    dislikes: 18,
    details: {
      eatingSteps: ["김밥 한입 뒤 우유를 마시기"],
      tips: ["우유는 차가울수록 조합이 잘 맞아요."],
      cautions: ["호불호 있어요"],
      situationTags: ["간식 추천"],
      reviewPoints: ["⭐ 후회 없는 선택"],
    },
    topFiveEnteredAt: new Date("2026-05-22T20:00:00.000Z"),
    topWorstEnteredAt: new Date("2026-05-22T20:00:00.000Z"),
    createdAt: new Date("2026-05-22T19:10:00.000Z"),
    updatedAt: new Date("2026-05-22T19:10:00.000Z"),
  },
  {
    authorId: seedUserIds.ai3.toString(),
    authorNickname: seedUsers[2].nickname,
    authorProfileImageUrl: seedUsers[2].profileImageUrl,
    title: "샐러드랩 + 토마토주스 상쾌한 아침 조합",
    content: "생각보다 포만감이 괜찮고 아침에 부담이 적어요.",
    priceMin: 5600,
    priceMax: 5600,
    categories: ["건강", "아침 대용", "맛있게 먹었어요"],
    imageUrls: [
      "https://images.unsplash.com/photo-1512621776951-a57141f2eefd?auto=format&fit=crop&w=900&q=80",
    ],
    likes: 29,
    dislikes: 1,
    details: {
      eatingSteps: ["랩을 반으로 나눠 주스와 함께 먹기"],
      tips: ["주스는 차갑게 먹는 편이 잘 어울려요."],
      cautions: ["양이 적어요"],
      situationTags: ["아침 대용", "등교길 추천"],
      reviewPoints: ["💯 맛있게 먹었어요"],
    },
    createdAt: new Date("2026-05-23T08:14:00.000Z"),
    updatedAt: new Date("2026-05-23T08:14:00.000Z"),
  },
  {
    authorId: seedUserIds.ai4.toString(),
    authorNickname: seedUsers[3].nickname,
    authorProfileImageUrl: seedUsers[3].profileImageUrl,
    title: "컵닭갈비볶음면 + 콜라 자극 끝판 조합",
    content: "처음엔 맛있는데 끝으로 갈수록 느끼해서 물리는 타입이에요.",
    priceMin: 4900,
    priceMax: 4900,
    categories: ["최악순 후보", "생각보다 짜요", "야식 추천"],
    imageUrls: [
      "https://images.unsplash.com/photo-1617093727343-374698b1b08d?auto=format&fit=crop&w=900&q=80",
    ],
    likes: 12,
    dislikes: 27,
    details: {
      eatingSteps: ["면을 비빈 뒤 콜라와 번갈아 먹기"],
      tips: ["얼음이 있으면 조금 낫지만 금방 물려요."],
      cautions: ["생각보다 짜요", "호불호 있어요"],
      situationTags: ["야식 추천"],
      reviewPoints: ["👍 기대 이상이에요"],
    },
    topWorstEnteredAt: new Date("2026-05-23T22:00:00.000Z"),
    createdAt: new Date("2026-05-23T21:08:00.000Z"),
    updatedAt: new Date("2026-05-23T21:08:00.000Z"),
  },
  {
    authorId: seedUserIds.ai5.toString(),
    authorNickname: seedUsers[4].nickname,
    authorProfileImageUrl: seedUsers[4].profileImageUrl,
    title: "참깨라면 + 구운계란 해장 조합",
    content: "익숙한 맛이라 실패는 없는데 국물까지 먹으면 꽤 짭짤해요.",
    priceMin: 3000,
    priceMax: 3000,
    categories: ["짭짤", "한 끼로 딱이에요", "등교길 추천"],
    imageUrls: [
      "https://images.unsplash.com/photo-1607301405390-d831c242f59b?auto=format&fit=crop&w=900&q=80",
    ],
    likes: 35,
    dislikes: 8,
    details: {
      eatingSteps: ["라면에 계란을 잘라 넣어 같이 먹기"],
      tips: ["계란을 으깨면 국물이 더 고소해져요."],
      cautions: ["생각보다 짜요"],
      situationTags: ["등교길 추천", "점심 대용"],
      reviewPoints: ["🍽️ 한 끼로 딱이에요"],
    },
    createdAt: new Date("2026-05-24T06:58:00.000Z"),
    updatedAt: new Date("2026-05-24T06:58:00.000Z"),
  },
  {
    authorId: seedUserIds.ai6.toString(),
    authorNickname: seedUsers[5].nickname,
    authorProfileImageUrl: seedUsers[5].profileImageUrl,
    title: "한입두부 + 매실음료 속편한 조합",
    content: "과한 맛은 없지만 속이 편해서 밤에 먹기 괜찮았어요.",
    priceMin: 3500,
    priceMax: 3500,
    categories: ["건강", "야식 추천", "추천하고 싶어요"],
    imageUrls: [
      "https://images.unsplash.com/photo-1569288063643-5d29ad0e570e?auto=format&fit=crop&w=900&q=80",
    ],
    likes: 21,
    dislikes: 2,
    details: {
      eatingSteps: ["두부를 먼저 먹고 매실음료를 마시기"],
      tips: ["차갑게 먹어야 더 깔끔해요."],
      cautions: ["향이 강해요"],
      situationTags: ["야식 추천", "다이어트 할 때 추천"],
      reviewPoints: ["👏 추천하고 싶어요"],
    },
    createdAt: new Date("2026-05-24T23:20:00.000Z"),
    updatedAt: new Date("2026-05-24T23:20:00.000Z"),
  },
  {
    authorId: seedUserIds.ai7.toString(),
    authorNickname: seedUsers[6].nickname,
    authorProfileImageUrl: seedUsers[6].profileImageUrl,
    title: "복숭아아이스티 + 젤리빈 드라이브 조합",
    content: "가볍게 입 심심할 때 좋은데 달아서 천천히 먹는 게 나아요.",
    priceMin: 2800,
    priceMax: 2800,
    categories: ["달달", "드라이브 간식", "만족스러워요"],
    imageUrls: [
      "https://images.unsplash.com/photo-1499636136210-6f4ee915583e?auto=format&fit=crop&w=900&q=80",
    ],
    likes: 24,
    dislikes: 3,
    details: {
      eatingSteps: ["젤리빈을 조금씩 먹으며 아이스티 마시기"],
      tips: ["얼음컵에 옮기면 훨씬 시원해요."],
      cautions: ["생각보다 달아요"],
      situationTags: ["드라이브 간식", "간식 추천"],
      reviewPoints: ["🥰 만족스러워요"],
    },
    createdAt: new Date("2026-05-25T15:12:00.000Z"),
    updatedAt: new Date("2026-05-25T15:12:00.000Z"),
  },
  {
    authorId: seedUserIds.ai1.toString(),
    authorNickname: seedUsers[0].nickname,
    authorProfileImageUrl: seedUsers[0].profileImageUrl,
    title: "딸기샌드 + 저지방우유 시험기간 조합",
    content: "자극적이지 않고 손에 잘 묻지 않아서 책상에서 먹기 편했어요.",
    priceMin: 4100,
    priceMax: 4100,
    categories: ["달달", "공부할 때 추천", "가격 대비 만족"],
    imageUrls: [
      "https://images.unsplash.com/photo-1509440159596-0249088772ff?auto=format&fit=crop&w=900&q=80",
    ],
    likes: 38,
    dislikes: 5,
    details: {
      eatingSteps: ["샌드를 반으로 나눠 우유와 번갈아 먹기"],
      tips: ["샌드는 차갑게 먹어야 식감이 좋아요."],
      cautions: ["양이 적어요"],
      situationTags: ["공부할 때 추천", "간식 추천"],
      reviewPoints: ["👍 가격 대비 만족"],
    },
    createdAt: new Date("2026-05-26T00:44:00.000Z"),
    updatedAt: new Date("2026-05-26T00:44:00.000Z"),
  },
];

const HACCP_SERVICE_KEY = String(process.env.HACCP_SERVICE_KEY || "").trim();
const UPCITEMDB_API_KEY = String(process.env.UPCITEMDB_API_KEY || "").trim();
const OPENAI_API_KEY = String(process.env.OPENAI_API_KEY || "").trim();
const OPENAI_MODEL = String(process.env.OPENAI_MODEL || "gpt-5.2").trim();
const OPENAI_BOT_MODEL = String(
  process.env.OPENAI_BOT_MODEL || "gpt-5.4-mini"
).trim();
const PRODUCT_LOOKUP_SOURCES = [
  "haccp-public-data",
  "open-food-facts",
];
const CU_AUTO_CRAWL_ENABLED = String(process.env.CU_AUTO_CRAWL_ENABLED || "false") === "true";
const CU_CRAWL_INTERVAL_HOURS = Math.max(Number(process.env.CU_CRAWL_INTERVAL_HOURS || 168), 1);

function serializePost(post, currentUser = null) {
  const likedPostIds = new Set((currentUser?.likedPostIds || []).map(String));
  const dislikedPostIds = new Set((currentUser?.dislikedPostIds || []).map(String));
  const postId = post._id.toString();
  return {
    id: postId,
    authorId: post.authorId,
    authorNickname: post.authorNickname,
    authorProfileImageUrl: post.authorProfileImageUrl,
    title: post.title,
    content: post.content,
    priceMin: post.priceMin,
    priceMax: post.priceMax,
    categories: post.categories,
    likes: post.likes,
    dislikes: post.dislikes,
    comments: post.comments.map((comment) => ({
      authorId: comment.authorId || "",
      authorNickname: comment.authorNickname || "익명",
      authorProfileImageUrl: comment.authorProfileImageUrl || null,
      text: comment.text,
      createdAt: comment.createdAt,
    })),
    reviews: (post.reviews || []).map((review) => ({
      id: review.id,
      authorId: review.authorId,
      authorNickname: review.authorNickname,
      text: review.text,
      rating: review.rating,
      tags: review.tags || [],
      sweet: review.sweet,
      salty: review.salty,
      spicy: review.spicy,
      sour: review.sour,
      caution: review.caution,
      createdAt: review.createdAt,
    })),
    calories: post.calories ?? null,
    rating: post.rating || 0,
    createdAt: post.createdAt,
    imageData: post.imageData,
    imageUrl: post.imageUrl,
    imageDatas: (post.imageDatas && post.imageDatas.length > 0)
      ? post.imageDatas
      : (post.imageData ? [post.imageData] : []),
    imageUrls: (post.imageUrls && post.imageUrls.length > 0)
      ? post.imageUrls
      : (post.imageUrl ? [post.imageUrl] : []),
    details: post.details || {
      eatingSteps: [],
      tips: [],
      cautions: [],
      situationTags: [],
      reviewPoints: [],
      prepTimeTag: "",
    },
    likedByMe: likedPostIds.has(postId),
    dislikedByMe: dislikedPostIds.has(postId),
    topFiveEnteredAt: post.topFiveEnteredAt,
    topWorstEnteredAt: post.topWorstEnteredAt,
  };
}

function serializePostFeatureInfo(post) {
  const recentLikeCutoff = Date.now() - (7 * 24 * 60 * 60 * 1000);
  return {
    id: post._id.toString(),
    authorId: post.authorId,
    title: post.title,
    likes: Number(post.likes || 0),
    dislikes: Number(post.dislikes || 0),
    commentCount: (post.comments || []).length,
    reviewCount: (post.reviews || []).length,
    recentLikeCount: (post.likeEvents || []).filter(
      (event) => new Date(event.createdAt).getTime() >= recentLikeCutoff
    ).length,
    createdAt: post.createdAt,
    topFiveEnteredAt: post.topFiveEnteredAt || null,
    topWorstEnteredAt: post.topWorstEnteredAt || null,
  };
}

function requestOrigin(req) {
  const forwardedProto = String(req.get("x-forwarded-proto") || "")
    .split(",")[0]
    .trim();
  return `${forwardedProto || req.protocol}://${req.get("host")}`;
}

function serializePostCatalog(post, currentUser, req) {
  const postId = post._id.toString();
  const likedPostIds = new Set((currentUser?.likedPostIds || []).map(String));
  const dislikedPostIds = new Set((currentUser?.dislikedPostIds || []).map(String));
  const remoteImageUrls = (post.imageUrls && post.imageUrls.length > 0)
    ? post.imageUrls.filter(Boolean)
    : (post.imageUrl ? [post.imageUrl] : []);
  const storedImageCount = (post.imageDatas && post.imageDatas.length > 0)
    ? post.imageDatas.length
    : (post.imageData ? 1 : 0);
  const storedImageUrls = Array.from(
    { length: storedImageCount },
    (_, index) => `${requestOrigin(req)}/api/posts/${postId}/images/${index}`
  );
  const imageUrls = [...remoteImageUrls, ...storedImageUrls];

  return {
    id: postId,
    authorId: post.authorId,
    authorNickname: post.authorNickname,
    authorProfileImageUrl: post.authorProfileImageUrl || null,
    title: post.title,
    content: post.content || "",
    priceMin: Number(post.priceMin || 0),
    priceMax: Number(post.priceMax || 0),
    categories: post.categories || [],
    likes: Number(post.likes || 0),
    dislikes: Number(post.dislikes || 0),
    comments: post.comments || [],
    reviews: post.reviews || [],
    calories: post.calories ?? null,
    rating: Number(post.rating || 0),
    createdAt: post.createdAt,
    imageData: null,
    imageUrl: imageUrls[0] || null,
    imageDatas: [],
    imageUrls,
    details: post.details || {},
    likedByMe: likedPostIds.has(postId),
    dislikedByMe: dislikedPostIds.has(postId),
    topFiveEnteredAt: post.topFiveEnteredAt || null,
    topWorstEnteredAt: post.topWorstEnteredAt || null,
  };
}

function serializeProduct(product, { cached }) {
  return {
    barcode: product.barcode,
    officialName: product.officialName,
    normalizedName: product.normalizedName,
    brand: product.brand,
    manufacturer: product.manufacturer,
    seller: product.seller,
    store: product.store,
    capacity: product.capacity,
    price:
      product.price !== null && product.price !== undefined && Number.isFinite(Number(product.price))
        ? Number(product.price)
        : null,
    calories:
      product.calories !== null && product.calories !== undefined && Number.isFinite(Number(product.calories))
        ? Math.round(Number(product.calories))
        : null,
    aliases: product.aliases,
    categories: product.categories,
    images: product.images,
    source: product.source,
    sources: (product.sources || []).map((source) => ({
      source: source.source,
      officialName: source.officialName || null,
      store: source.store || null,
      price: source.price ?? null,
      calories: source.calories ?? null,
      checkedAt: source.checkedAt || null,
    })),
    verificationStatus: product.verificationStatus,
    lookupCount: product.lookupCount,
    tentative: Boolean(product.tentative),
    warning: product.warning || null,
    cached,
    lastVerifiedAt: product.lastVerifiedAt,
  };
}

async function hydratePostAuthorImages(posts) {
  const postList = Array.isArray(posts) ? posts : [posts];
  const authorIds = new Set();

  for (const post of postList) {
    if (post?.authorId && mongoose.Types.ObjectId.isValid(String(post.authorId))) {
      authorIds.add(String(post.authorId));
    }
    for (const comment of post?.comments || []) {
      if (comment?.authorId && mongoose.Types.ObjectId.isValid(String(comment.authorId))) {
        authorIds.add(String(comment.authorId));
      }
    }
  }

  if (authorIds.size === 0) {
    return postList;
  }

  const users = await User.find({ _id: { $in: Array.from(authorIds) } })
    .select("_id profileImageUrl")
    .lean();
  const authorImageById = new Map(
    users.map((user) => [user._id.toString(), user.profileImageUrl || null]),
  );

  for (const post of postList) {
    if (post?.authorId) {
      const freshProfileImageUrl = authorImageById.get(String(post.authorId));
      if (typeof freshProfileImageUrl !== "undefined") {
        post.authorProfileImageUrl = freshProfileImageUrl;
      }
    }

    for (const comment of post?.comments || []) {
      if (!comment?.authorId) continue;
      const freshProfileImageUrl = authorImageById.get(String(comment.authorId));
      if (typeof freshProfileImageUrl !== "undefined") {
        comment.authorProfileImageUrl = freshProfileImageUrl;
      }
    }
  }

  return postList;
}

async function serializeUser(user) {
  const pickedByCount = await User.countDocuments({ pickedAuthorIds: user._id.toString() });
  return {
    id: user._id.toString(),
    username: user.username,
    password: "",
    nickname: user.nickname,
    profileImageUrl: user.profileImageUrl,
    botSetup: user.botSetup,
    memoryNotes: user.memoryNotes || [],
    botMessages: user.botMessages || [],
    archivedConversations: user.archivedConversations || [],
    likedPostIds: user.likedPostIds || [],
    dislikedPostIds: user.dislikedPostIds || [],
    savedPostIds: user.savedPostIds || [],
    pickedAuthorIds: user.pickedAuthorIds || [],
    battleState: user.battleState || {},
    profilePublic: user.profilePublic !== false,
    profileVisibility: user.profileVisibility || {
      username: false,
      likes: true,
      dislikes: false,
      saved: false,
      myPosts: true,
      picks: true,
      pickedBy: true,
    },
    pickedByCount,
  };
}

function normalizeBarcode(input) {
  return String(input || "").replace(/[^0-9A-Za-z]/g, "");
}

function normalizeName(input) {
  return String(input || "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, " ")
    .replace(/[()[\]{}]/g, "")
    .trim();
}

function compactStrings(items) {
  return [...new Set((items || []).map((item) => String(item || "").trim()).filter(Boolean))];
}

function extractClovaTexts(payload) {
  const lines = [];
  const images = Array.isArray(payload?.images) ? payload.images : [];

  for (const image of images) {
    const fields = Array.isArray(image?.fields) ? image.fields : [];
    for (const field of fields) {
      const text = String(field?.inferText || "").trim();
      if (text) lines.push(text);
    }

    const tables = Array.isArray(image?.tables) ? image.tables : [];
    for (const table of tables) {
      const cells = Array.isArray(table?.cells) ? table.cells : [];
      for (const cell of cells) {
        const cellText = String(cell?.cellTextLines?.map((line) => line?.cellWords?.map((word) => word?.inferText || "").join(" ")).join(" ") || "")
          .trim();
        if (cellText) lines.push(cellText);
      }
    }
  }

  return compactStrings(lines);
}

function buildSearchTokens(candidate) {
  return compactStrings([
    candidate.officialName,
    candidate.brand,
    candidate.manufacturer,
    candidate.seller,
    candidate.store,
    candidate.capacity,
    ...(candidate.aliases || []),
    ...(candidate.categories || []),
  ]).map(normalizeName).filter(Boolean);
}

function hashPassword(password) {
  return bcrypt.hashSync(String(password), 12);
}

function legacyPasswordHash(password) {
  return crypto.createHash("sha256").update(String(password)).digest("hex");
}

function passwordMatches(password, passwordHash) {
  const stored = String(passwordHash || "");
  if (stored.startsWith("$2")) {
    return bcrypt.compareSync(String(password), stored);
  }
  return stored === legacyPasswordHash(password);
}

function createAuthToken(user) {
  return jwt.sign(
    { sub: user._id.toString(), username: user.username },
    JWT_SECRET,
    { expiresIn: "30d", issuer: "pyeonpick-api" }
  );
}

function requireAuth(req, res, next) {
  const authorization = String(req.headers.authorization || "");
  const token = authorization.startsWith("Bearer ")
    ? authorization.slice(7)
    : "";
  if (!token) {
    return res.status(401).json({ message: "로그인이 필요합니다." });
  }
  try {
    req.auth = jwt.verify(token, JWT_SECRET, { issuer: "pyeonpick-api" });
    return next();
  } catch (_) {
    return res.status(401).json({ message: "로그인이 만료되었어요. 다시 로그인해 주세요." });
  }
}

function requireSelf(req, res, next) {
  if (String(req.auth?.sub || "") !== String(req.params.id || "")) {
    return res.status(403).json({ message: "본인 계정만 확인할 수 있어요." });
  }
  return next();
}

function encodePostCursor(post, sort) {
  const payload = {
    sort,
    id: post._id.toString(),
    createdAt: post.createdAt.toISOString(),
    likes: post.likes,
    dislikes: post.dislikes,
  };
  return Buffer.from(JSON.stringify(payload)).toString("base64url");
}

function decodePostCursor(cursor) {
  try {
    const raw = Buffer.from(String(cursor), "base64url").toString("utf8");
    return JSON.parse(raw);
  } catch (_) {
    return null;
  }
}

function buildPostCursorFilter(sort, cursor) {
  if (!cursor) return null;

  const cursorId = new mongoose.Types.ObjectId(String(cursor.id));
  const cursorDate = new Date(cursor.createdAt);

  if (sort === "popular") {
    return {
      $or: [
        { likes: { $lt: Number(cursor.likes || 0) } },
        { likes: Number(cursor.likes || 0), createdAt: { $lt: cursorDate } },
        { likes: Number(cursor.likes || 0), createdAt: cursorDate, _id: { $lt: cursorId } },
      ],
    };
  }

  if (sort === "worst") {
    return {
      $or: [
        { dislikes: { $lt: Number(cursor.dislikes || 0) } },
        { dislikes: Number(cursor.dislikes || 0), createdAt: { $lt: cursorDate } },
        { dislikes: Number(cursor.dislikes || 0), createdAt: cursorDate, _id: { $lt: cursorId } },
      ],
    };
  }

  return {
    $or: [
      { createdAt: { $lt: cursorDate } },
      { createdAt: cursorDate, _id: { $lt: cursorId } },
    ],
  };
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

function parseOpenFoodFactsCalories(product) {
  const nutriments = product?.nutriments || {};
  const servingCalories = Number(nutriments["energy-kcal_serving"]);
  if (Number.isFinite(servingCalories) && servingCalories > 0) {
    return Math.round(servingCalories);
  }

  const packageWeight = String(product?.quantity || "").match(/([0-9]+(?:\.[0-9]+)?)\s*g\b/i);
  const per100gCalories = Number(nutriments["energy-kcal_100g"]);
  if (packageWeight && Number.isFinite(per100gCalories) && per100gCalories > 0) {
    return Math.round((per100gCalories * Number(packageWeight[1])) / 100);
  }
  return null;
}

async function fetchProductFromOpenFoodFacts(barcode) {
  const response = await fetch(`https://world.openfoodfacts.org/api/v2/product/${barcode}.json`, {
    headers: {
      "User-Agent": "PyeonPick/1.0 (barcode lookup for convenience food app)",
    },
    signal: AbortSignal.timeout(7000),
  });

  if (response.status === 404) {
    return null;
  }

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
  const imageUrl =
    product?.image_front_url ||
    product?.image_url ||
    product?.selected_images?.front?.display?.ko ||
    product?.selected_images?.front?.display?.en ||
    null;
  const categories = compactStrings(
    [product?.categories]
      .concat(product?.categories_tags || [])
      .flatMap((entry) => String(entry || "").split(","))
      .map((entry) => String(entry).replace(/^en:/, "").trim())
  );

  return {
    barcode,
    officialName: officialName.trim(),
    brand: brand || null,
    manufacturer: null,
    seller: null,
    store,
    capacity: product?.quantity ? String(product.quantity).trim() : null,
    price: null,
    calories: parseOpenFoodFactsCalories(product),
    aliases: compactStrings([product?.abbreviated_product_name, product?.product_name_en]),
    categories,
    images: {
      product: imageUrl,
      meta: null,
    },
    source: "open-food-facts",
    verificationStatus: "auto-imported",
    raw: product,
    lastVerifiedAt: new Date(),
  };
}

function decodeHtml(value) {
  return String(value || "")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
}

function extractXmlValue(xml, tagName) {
  const match = String(xml).match(new RegExp(`<${tagName}>([\\s\\S]*?)</${tagName}>`, "i"));
  if (!match) return null;
  return decodeHtml(match[1]).trim();
}

function extractXmlItems(xml) {
  return [...String(xml).matchAll(/<item>([\s\S]*?)<\/item>/gi)].map((match) => match[1]);
}

async function fetchProductFromHaccp(barcode) {
  if (!HACCP_SERVICE_KEY) {
    return null;
  }

  const normalizedBarcode = barcode.replace(/\s+/g, "");
  let matchedItem = null;
  const pageSize = 100;
  let pageNo = 1;
  let maxPages = 1;

  while (pageNo <= maxPages && !matchedItem) {
    const url = new URL("https://apis.data.go.kr/B553748/CertImgListServiceV3/getCertImgListServiceV3");
    url.searchParams.set("serviceKey", HACCP_SERVICE_KEY);
    url.searchParams.set("pageNo", String(pageNo));
    url.searchParams.set("numOfRows", String(pageSize));
    url.searchParams.set("barcode", barcode);

    const response = await fetch(url, {
      headers: {
        "User-Agent": "PyeonPick/1.0 (barcode lookup for convenience food app)",
        Accept: "application/xml,text/xml;q=0.9,*/*;q=0.8",
      },
      signal: AbortSignal.timeout(8000),
    });

    if (!response.ok) {
      throw new Error(`HACCP lookup failed with status ${response.status}`);
    }

    const xml = await response.text();
    const resultCode = extractXmlValue(xml, "resultCode");
    if (resultCode && resultCode !== "00" && resultCode.toUpperCase() !== "OK") {
      throw new Error(`HACCP lookup failed with result code ${resultCode}`);
    }

    const items = extractXmlItems(xml);
    matchedItem = items.find((itemXml) => {
      const itemBarcode = extractXmlValue(itemXml, "barcode");
      return itemBarcode && itemBarcode.replace(/[^0-9A-Za-z]/g, "") === normalizedBarcode;
    }) || null;

    if (!matchedItem && items.length < pageSize) {
      break;
    }

    pageNo += 1;
  }

  if (!matchedItem) {
    return null;
  }

  const officialName = extractXmlValue(matchedItem, "prdlstNm");
  if (!officialName) {
    return null;
  }

  const manufacturer = extractXmlValue(matchedItem, "manufacture");
  const seller = extractXmlValue(matchedItem, "seller");
  const brand = seller || manufacturer;
  const imageUrl = extractXmlValue(matchedItem, "imgurl1") || extractXmlValue(matchedItem, "imgurl2");
  const metaImageUrl = extractXmlValue(matchedItem, "imgurl2");
  const capacity = extractXmlValue(matchedItem, "capacity");
  const category = extractXmlValue(matchedItem, "prdkind");

  return {
    barcode,
    officialName,
    brand,
    manufacturer,
    seller,
    store: null,
    aliases: [],
    capacity,
    price: null,
    calories: null,
    categories: compactStrings([category]),
    images: {
      product: imageUrl,
      meta: metaImageUrl,
    },
    source: "haccp-public-data",
    verificationStatus: "official-public",
    raw: {
      xml: matchedItem,
      imageUrl,
    },
    lastVerifiedAt: new Date(),
  };
}

async function fetchProductFromGoUpc(barcode) {
  return null;
}

async function fetchProductFromUpcItemDb(barcode) {
  if (!UPCITEMDB_API_KEY) {
    return null;
  }

  const response = await fetch(`https://api.upcitemdb.com/prod/trial/lookup?upc=${barcode}`, {
    headers: {
      "user_key": UPCITEMDB_API_KEY,
      "User-Agent": "PyeonPick/1.0 (barcode lookup for convenience food app)",
      Accept: "application/json",
    },
    signal: AbortSignal.timeout(7000),
  });

  if (response.status === 404) {
    return null;
  }
  if (!response.ok) {
    throw new Error(`UPCitemdb lookup failed with status ${response.status}`);
  }

  const payload = await response.json();
  const item = Array.isArray(payload?.items) ? payload.items[0] : null;
  const officialName = item?.title || item?.name || "";
  if (!officialName) {
    return null;
  }

  return {
    barcode,
    officialName: String(officialName).trim(),
    brand: item?.brand ? String(item.brand).trim() : null,
    manufacturer: null,
    seller: null,
    store: null,
    aliases: [],
    capacity: item?.size ? String(item.size).trim() : null,
    categories: compactStrings([item?.category]),
    images: {
      product: item?.images?.[0] || null,
      meta: null,
    },
    source: "upcitemdb",
    verificationStatus: "third-party",
    raw: payload,
    lastVerifiedAt: new Date(),
  };
}

async function fetchProductFromProviders(barcode) {
  const providers = [
    fetchProductFromHaccp,
    fetchProductFromOpenFoodFacts,
  ];

  const errors = [];
  const candidates = await Promise.all(
    providers.map(async (provider) => {
      try {
        return await provider(barcode);
      } catch (error) {
        errors.push(`${provider.name}: ${error.message}`);
        return null;
      }
    })
  );
  const available = candidates.filter(Boolean);
  if (available.length === 0) return { product: null, errors };

  const product = { ...available[0] };
  for (const candidate of available.slice(1)) {
    product.price = product.price ?? candidate.price ?? null;
    product.calories = product.calories ?? candidate.calories ?? null;
    product.store = product.store || candidate.store || null;
    product.capacity = product.capacity || candidate.capacity || null;
    product.images = {
      product: product.images?.product || candidate.images?.product || null,
      meta: product.images?.meta || candidate.images?.meta || null,
    };
    product.aliases = compactStrings([...(product.aliases || []), ...(candidate.aliases || [])]);
    product.categories = compactStrings([...(product.categories || []), ...(candidate.categories || [])]);
  }
  return { product, errors };
}

function tryParseJsonObject(text) {
  const raw = String(text || "").trim();
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch (_) {
    const fenced = raw.match(/```(?:json)?\s*([\s\S]*?)```/i);
    if (fenced) {
      try {
        return JSON.parse(fenced[1].trim());
      } catch (_) {}
    }
    const objectMatch = raw.match(/\{[\s\S]*\}/);
    if (objectMatch) {
      try {
        return JSON.parse(objectMatch[0]);
      } catch (_) {}
    }
  }
  return null;
}

function extractResponsesText(payload) {
  if (typeof payload?.output_text === "string" && payload.output_text.trim()) {
    return payload.output_text;
  }

  const parts = [];
  for (const item of Array.isArray(payload?.output) ? payload.output : []) {
    for (const content of Array.isArray(item?.content) ? item.content : []) {
      if (
        (content?.type === "output_text" || content?.type === "text") &&
        typeof content.text === "string"
      ) {
        parts.push(content.text);
      }
    }
  }
  return parts.join("\n").trim();
}

function analyzeBotPromptLocally(prompt) {
  const text = String(prompt || "").trim();
  const amountMatch = text.match(/(\d+(?:\.\d+)?)\s*(만|천)?\s*원?/);
  let budget = null;
  if (amountMatch) {
    const multiplier = amountMatch[2] === "만" ? 10000 : amountMatch[2] === "천" ? 1000 : 1;
    const parsed = Math.round(Number(amountMatch[1]) * multiplier);
    if (parsed >= 500) budget = parsed;
  }
  const timeMatch = text.match(/(\d+)\s*분/);
  const wantedTastes = [
    ["달달", /달달|달콤|단맛|단 거/],
    ["매콤", /매콤|매운|불닭/],
    ["새콤", /새콤|상큼|신맛/],
    ["짭짤", /짭짤|짠맛|짠 거/],
  ].filter(([, pattern]) => pattern.test(text)).map(([taste]) => taste);
  let emotion = "neutral";
  if (/피곤|지쳤|졸려|힘들/.test(text)) emotion = "tired";
  else if (/스트레스|짜증|화나/.test(text)) emotion = "stressed";
  else if (/불안|긴장|걱정/.test(text)) emotion = "anxious";
  else if (/아파|속이 안|몸이 안/.test(text)) emotion = "sick";
  else if (/외로|쓸쓸/.test(text)) emotion = "lonely";
  else if (/슬퍼|우울/.test(text)) emotion = "sad";
  else if (/신나|기뻐|행복/.test(text)) emotion = "happy";

  const lateNight = /야식|새벽|밤늦|밤에/.test(text);
  const mealPurpose = /간식/.test(text)
    ? "간식"
    : /야식/.test(text)
      ? "야식"
      : /아침/.test(text)
        ? "아침"
        : /점심/.test(text)
          ? "점심"
          : /저녁/.test(text)
            ? "저녁"
            : null;
  const bodyCondition = emotion === "sick" ? "몸 상태가 좋지 않음" : null;
  const summary = emotion === "neutral"
    ? "말해준 조건을 기준으로 지금 잘 맞는 편의점 조합을 찾아볼게요."
    : "지금 기분과 상황을 반영해서 부담 없이 고를 수 있는 조합을 찾아볼게요.";

  return {
    emotion,
    budget,
    timeAvailableMinutes: timeMatch ? Number(timeMatch[1]) : null,
    lateNight,
    mealPurpose,
    bodyCondition,
    wantedTastes,
    avoidConditions: [],
    summary,
  };
}

async function fetchProductFromOpenAITemporary(barcode) {
  if (!OPENAI_API_KEY) {
    return null;
  }

  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${OPENAI_API_KEY}`,
    },
    body: JSON.stringify({
      model: OPENAI_MODEL,
      tools: [{ type: "web_search" }],
      tool_choice: "auto",
      input: [
        {
          role: "developer",
          content: [
            {
              type: "input_text",
              text:
                "You are helping a Korean convenience-store app identify a product from a barcode. Search the web and return only a JSON object. Prefer exact Korean official product names. Never include price, shipping, purchase prompts, mall descriptions, or marketing copy. If uncertain, set low confidence and keep the most likely Korean product name. Output schema: {\"officialName\":\"string\",\"brand\":\"string|null\",\"confidence\":\"high|medium|low\",\"reason\":\"string\"}.",
            },
          ],
        },
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: `Identify the official Korean product name for barcode ${barcode}. Search the web if needed and return JSON only.`,
            },
          ],
        },
      ],
    }),
    signal: AbortSignal.timeout(8000),
  });

  if (!response.ok) {
    throw new Error(`OpenAI temporary lookup failed with status ${response.status}`);
  }

  const payload = await response.json();
  const outputText = extractResponsesText(payload);
  const parsed = tryParseJsonObject(outputText);
  const officialName = String(parsed?.officialName || "").trim();
  if (!officialName) {
    return null;
  }

  return {
    barcode,
    officialName,
    normalizedName: normalizeName(officialName),
    brand: parsed?.brand ? String(parsed.brand).trim() : null,
    manufacturer: null,
    seller: null,
    store: null,
    capacity: null,
    aliases: [],
    categories: [],
    images: { product: null, meta: null },
    source: "openai-web-search-temporary",
    sources: [],
    verificationStatus: "temporary-openai-web-search",
    lookupCount: 0,
    raw: {
      openaiResponseId: payload.id || null,
      outputText,
      parsed,
    },
    lastVerifiedAt: new Date(),
    tentative: true,
    warning: "ChatGPT 웹검색 결과를 바탕으로 임시 추정한 상품명입니다. 정확하지 않을 수 있어요.",
  };
}

function toSourceEntry(candidate) {
  return {
    source: candidate.source,
    officialName: candidate.officialName || null,
    brand: candidate.brand || null,
    manufacturer: candidate.manufacturer || null,
    seller: candidate.seller || null,
    store: candidate.store || null,
    capacity: candidate.capacity || null,
    price: candidate.price ?? null,
    calories: candidate.calories ?? null,
    categories: compactStrings(candidate.categories || []),
    aliases: compactStrings(candidate.aliases || []),
    imageUrl: candidate.images?.product || null,
    metaImageUrl: candidate.images?.meta || null,
    checkedAt: candidate.lastVerifiedAt || new Date(),
    raw: candidate.raw || null,
  };
}

function mergeCandidateIntoProduct(existingProduct, candidate) {
  const mergedAliases = compactStrings([...(existingProduct.aliases || []), ...(candidate.aliases || [])]);
  const mergedCategories = compactStrings([...(existingProduct.categories || []), ...(candidate.categories || [])]);
  const mergedSearchTokens = compactStrings([...(existingProduct.searchTokens || []), ...buildSearchTokens(candidate)]);
  const mergedSources = [...(existingProduct.sources || [])];
  const nextSourceEntry = toSourceEntry(candidate);
  const existingSourceIndex = mergedSources.findIndex((entry) => entry.source === candidate.source);

  if (existingSourceIndex >= 0) {
    mergedSources[existingSourceIndex] = nextSourceEntry;
  } else {
    mergedSources.push(nextSourceEntry);
  }

  existingProduct.officialName = existingProduct.officialName || candidate.officialName;
  existingProduct.normalizedName = normalizeName(existingProduct.officialName || candidate.officialName);
  existingProduct.brand = existingProduct.brand || candidate.brand || null;
  existingProduct.manufacturer = existingProduct.manufacturer || candidate.manufacturer || null;
  existingProduct.seller = existingProduct.seller || candidate.seller || null;
  existingProduct.store = existingProduct.store || candidate.store || null;
  existingProduct.capacity = existingProduct.capacity || candidate.capacity || null;
  existingProduct.price = existingProduct.price ?? candidate.price ?? null;
  existingProduct.calories = existingProduct.calories ?? candidate.calories ?? null;
  existingProduct.aliases = mergedAliases;
  existingProduct.categories = mergedCategories;
  existingProduct.images = {
    product: existingProduct.images?.product || candidate.images?.product || null,
    meta: existingProduct.images?.meta || candidate.images?.meta || null,
  };
  existingProduct.searchTokens = mergedSearchTokens;
  existingProduct.source = candidate.source;
  existingProduct.sources = mergedSources;
  existingProduct.verificationStatus = existingProduct.verificationStatus || candidate.verificationStatus || "auto-imported";
  existingProduct.raw = candidate.raw || existingProduct.raw || null;
  existingProduct.lastVerifiedAt = candidate.lastVerifiedAt || new Date();
  existingProduct.lookupCount = Number(existingProduct.lookupCount || 0) + 1;
  return existingProduct;
}

async function upsertProductCandidate(barcode, candidate) {
  const existing = await Product.findOne({ barcode });
  if (existing) {
    mergeCandidateIntoProduct(existing, candidate);
    await existing.save();
    return existing;
  }

  const product = await Product.create({
    barcode,
    officialName: candidate.officialName,
    normalizedName: normalizeName(candidate.officialName),
    brand: candidate.brand || null,
    manufacturer: candidate.manufacturer || null,
    seller: candidate.seller || null,
    store: candidate.store || null,
    capacity: candidate.capacity || null,
    price: candidate.price ?? null,
    calories: candidate.calories ?? null,
    aliases: compactStrings(candidate.aliases || []),
    categories: compactStrings(candidate.categories || []),
    images: {
      product: candidate.images?.product || null,
      meta: candidate.images?.meta || null,
    },
    searchTokens: buildSearchTokens(candidate),
    source: candidate.source,
    sources: [toSourceEntry(candidate)],
    verificationStatus: candidate.verificationStatus || "auto-imported",
    lookupCount: 1,
    raw: candidate.raw || null,
    lastVerifiedAt: candidate.lastVerifiedAt || new Date(),
  });

  return product;
}

async function recordProductLookupMiss(barcode, checkedSources, errors) {
  await ProductLookupMiss.findOneAndUpdate(
    { barcode },
    {
      $inc: { failureCount: 1 },
      $set: {
        checkedSources,
        lastErrorMessages: errors.slice(0, 10),
        lastTriedAt: new Date(),
      },
      $setOnInsert: {
        firstSeenAt: new Date(),
      },
    },
    { upsert: true, new: true, setDefaultsOnInsert: true }
  );
}

const CU_AJAX_BASE_URL = "https://cu.bgfretail.com";
const CU_BROWSER_UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";
const CU_CATEGORY_CODES = ["10", "20", "30", "40", "50", "60", "70"];
const CU_MAX_PAGES_PER_SOURCE = Number(process.env.CU_MAX_PAGES_PER_SOURCE || 80);

function serializeCuProduct(product) {
  return {
    id: product.id,
    store: "CU",
    productId: product.productId,
    name: product.name,
    price: product.price,
    imageUrl: product.imageUrl || null,
    barcode: product.barcode || null,
    isNewFlag: Boolean(product.isNewFlag || product.isNewByDiff),
    siteNewFlag: Boolean(product.isNewFlag),
    diffNewFlag: Boolean(product.isNewByDiff),
    isPb: Boolean(product.isPb),
    categoryCode: product.categoryCode || null,
    firstSeenAt: product.firstSeenAt,
    lastSeenAt: product.lastSeenAt,
    lastCrawledAt: product.lastCrawledAt,
  };
}

function decodeHtmlText(value) {
  return String(value || "")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/\s+/g, " ")
    .trim();
}

function absoluteCuImageUrl(src) {
  const value = String(src || "").trim();
  if (!value) return null;
  if (/^https?:\/\//i.test(value)) return value;
  if (value.startsWith("//")) return `https:${value}`;
  return `${CU_AJAX_BASE_URL}${value.startsWith("/") ? "" : "/"}${value}`;
}

function extractCuBarcode(imageUrl) {
  const match = String(imageUrl || "").match(/\/([0-9]{8,14})\.[a-z0-9]+(?:\?|$)/i);
  return match ? match[1] : null;
}

function parseCuProductAnchors(html, { isPb = false, categoryCode = null } = {}) {
  const products = [];
  const seenProductIds = new Set();
  const listItemPattern = /<li\b[^>]*class=["'][^"']*\bprod_list\b[^"']*["'][^>]*>([\s\S]*?)<\/li>/gi;
  let listItemMatch;

  while ((listItemMatch = listItemPattern.exec(String(html || ""))) !== null) {
    const itemHtml = listItemMatch[1] || "";
    const idMatch = itemHtml.match(/onclick=["']view\((\d+)\);?["']/i);
    const nameMatch = itemHtml.match(/<div\b[^>]*class=["'][^"']*\bname\b[^"']*["'][^>]*>[\s\S]*?<p[^>]*>([\s\S]*?)<\/p>/i);
    const priceMatch = itemHtml.match(/<div\b[^>]*class=["'][^"']*\bprice\b[^"']*["'][^>]*>[\s\S]*?<strong[^>]*>([\s\S]*?)<\/strong>/i);
    if (!idMatch || !nameMatch || !priceMatch) continue;

    const productId = idMatch[1];
    const imageMatch = itemHtml.match(/<img\b[^>]*src=["']([^"']+)["'][^>]*>/i);
    const imageUrl = absoluteCuImageUrl(imageMatch?.[1] || "");
    const name = decodeHtmlText(nameMatch[1].replace(/<[^>]+>/g, " "));
    if (!name) continue;

    products.push({
      id: `cu-${productId}`,
      store: "CU",
      productId,
      name,
      normalizedName: normalizeName(name),
      price: decodeHtmlText(priceMatch[1].replace(/<[^>]+>/g, " ")),
      imageUrl,
      barcode: extractCuBarcode(imageUrl),
      isNewFlag: /\bnew\b/i.test(itemHtml) || /tag_new\.png/i.test(itemHtml),
      isPb,
      categoryCode,
      rawText: decodeHtmlText(itemHtml.replace(/<[^>]+>/g, " ")),
    });
    seenProductIds.add(productId);
  }

  const anchorPattern = /<a\b(?=[^>]*(?:href=["']javascript:view\((\d+)\);?["']|onclick=["']view\((\d+)\);?["']))[^>]*>([\s\S]*?)<\/a>/gi;
  let match;

  while ((match = anchorPattern.exec(String(html || ""))) !== null) {
    const productId = match[1] || match[2];
    if (seenProductIds.has(productId)) continue;
    const innerHtml = match[3] || "";
    const imageMatch = innerHtml.match(/<img\b[^>]*src=["']([^"']+)["'][^>]*>/i);
    const imageUrl = absoluteCuImageUrl(imageMatch?.[1] || "");
    const rawText = decodeHtmlText(innerHtml.replace(/<[^>]+>/g, " "));
    const priceMatch = rawText.match(/(.+?)\s*([0-9][0-9,]*)\s*원/i);
    if (!priceMatch) continue;

    const name = decodeHtmlText(
      priceMatch[1]
        .replace(/\bNew\b/gi, "")
        .replace(/\b[12]\s*\+\s*1\b/g, "")
        .replace(/\s+/g, " ")
        .trim()
    );
    if (!name) continue;

    products.push({
      id: `cu-${productId}`,
      store: "CU",
      productId,
      name,
      normalizedName: normalizeName(name),
      price: priceMatch[2],
      imageUrl,
      barcode: extractCuBarcode(imageUrl),
      isNewFlag: /\bNew\b/i.test(rawText),
      isPb,
      categoryCode,
      rawText,
    });
  }

  return products;
}

async function fetchCuAjaxProducts(endpointPath, form, referer) {
  const body = new URLSearchParams(form);
  const response = await fetch(`${CU_AJAX_BASE_URL}${endpointPath}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
      "User-Agent": CU_BROWSER_UA,
      Referer: referer,
      "X-Requested-With": "XMLHttpRequest",
    },
    body,
    signal: AbortSignal.timeout(10000),
  });

  if (!response.ok) {
    throw new Error(`CU ${endpointPath} failed with status ${response.status}`);
  }

  return response.text();
}

async function crawlCuCategory(categoryCode) {
  const collected = [];
  const seenProductIds = new Set();
  for (let pageIndex = 1; pageIndex <= CU_MAX_PAGES_PER_SOURCE; pageIndex += 1) {
    const html = await fetchCuAjaxProducts(
      "/product/productAjax.do",
      {
        pageIndex: String(pageIndex),
        searchMainCategory: categoryCode,
        searchSubCategory: "",
        listType: "0",
        searchCondition: "setA",
        searchUseYn: "",
        gdIdx: "0",
        codeParent: categoryCode,
        user_id: "",
        search1: "",
        search2: "",
        searchKeyword: "",
      },
      "https://cu.bgfretail.com/product/product.do?category=product&depth2=4&sf=N"
    );
    const pageProducts = parseCuProductAnchors(html, { categoryCode });
    if (pageProducts.length === 0) break;
    const newProducts = pageProducts.filter((product) => {
      if (seenProductIds.has(product.productId)) return false;
      seenProductIds.add(product.productId);
      return true;
    });
    if (newProducts.length === 0) break;
    collected.push(...newProducts);
  }
  return collected;
}

async function crawlCuPbProducts() {
  const collected = [];
  const seenProductIds = new Set();
  for (let pageIndex = 1; pageIndex <= CU_MAX_PAGES_PER_SOURCE; pageIndex += 1) {
    const html = await fetchCuAjaxProducts(
      "/product/pbAjax.do",
      {
        pageIndex: String(pageIndex),
        listType: "0",
        searchCondition: "",
        searchUseYn: "",
        gdIdx: "0",
        searchgubun: "PBG",
        search1: "",
        search2: "",
        searchKeyword: "",
      },
      "https://cu.bgfretail.com/product/pb.do?category=product&depth2=1&sf=N"
    );
    const pageProducts = parseCuProductAnchors(html, { isPb: true });
    if (pageProducts.length === 0) break;
    const newProducts = pageProducts.filter((product) => {
      if (seenProductIds.has(product.productId)) return false;
      seenProductIds.add(product.productId);
      return true;
    });
    if (newProducts.length === 0) break;
    collected.push(...newProducts);
  }
  return collected;
}

async function crawlCuProducts() {
  const productsById = new Map();
  const errors = [];
  const categoryResults = await Promise.all(
    CU_CATEGORY_CODES.map(async (categoryCode) => {
      try {
        return { categoryCode, products: await crawlCuCategory(categoryCode) };
      } catch (error) {
        errors.push({
          source: `category-${categoryCode}`,
          message: String(error.message || error),
        });
        return { categoryCode, products: [] };
      }
    })
  );

  for (const result of categoryResults) {
    for (const product of result.products) {
      productsById.set(product.productId, {
        ...(productsById.get(product.productId) || {}),
        ...product,
        isNewFlag: Boolean(product.isNewFlag || productsById.get(product.productId)?.isNewFlag),
        isPb: Boolean(product.isPb || productsById.get(product.productId)?.isPb),
      });
    }
  }

  let pbProducts = [];
  try {
    pbProducts = await crawlCuPbProducts();
  } catch (error) {
    errors.push({ source: "pb", message: String(error.message || error) });
  }
  for (const product of pbProducts) {
    productsById.set(product.productId, {
      ...(productsById.get(product.productId) || {}),
      ...product,
      isNewFlag: Boolean(product.isNewFlag || productsById.get(product.productId)?.isNewFlag),
      isPb: true,
    });
  }

  return {
    products: Array.from(productsById.values()),
    errors,
  };
}

async function refreshCuProducts() {
  const crawledAt = new Date();
  const hadSnapshot = (await CuProduct.estimatedDocumentCount()) > 0;
  const crawlResult = await crawlCuProducts();
  const crawledProducts = crawlResult.products;

  let inserted = 0;
  let updated = 0;
  let pbCount = 0;
  let newCount = 0;

  for (const product of crawledProducts) {
    const existing = await CuProduct.findOne({ productId: product.productId });
    const isNewByDiff = hadSnapshot && !existing;
    const isNewFlag = Boolean(product.isNewFlag || isNewByDiff);
    if (product.isPb) pbCount += 1;
    if (isNewFlag) newCount += 1;

    await CuProduct.findOneAndUpdate(
      { productId: product.productId },
      {
        $set: {
          id: product.id,
          store: "CU",
          productId: product.productId,
          name: product.name,
          normalizedName: product.normalizedName,
          price: product.price,
          imageUrl: product.imageUrl || null,
          barcode: product.barcode || null,
          isNewFlag,
          isNewByDiff,
          isPb: Boolean(product.isPb || existing?.isPb),
          categoryCode: product.categoryCode || existing?.categoryCode || null,
          lastSeenAt: crawledAt,
          lastCrawledAt: crawledAt,
          rawText: product.rawText || "",
        },
        $setOnInsert: {
          firstSeenAt: crawledAt,
        },
      },
      { upsert: true, returnDocument: "after", setDefaultsOnInsert: true }
    );

    if (existing) {
      updated += 1;
    } else {
      inserted += 1;
    }
  }

  const seededPosts = await seedCuProductCommunityPosts(crawledAt);

  return {
    crawledAt,
    total: crawledProducts.length,
    inserted,
    updated,
    newCount,
    pbCount,
    seededPosts,
    categoryCodes: CU_CATEGORY_CODES,
    errors: crawlResult.errors,
  };
}

function parseCuPriceToNumber(price) {
  const value = Number(String(price || "").replace(/[^0-9]/g, ""));
  return Number.isFinite(value) ? value : 0;
}

function cuProductPostContent(product) {
  const labels = [
    ...(product.isNewFlag || product.isNewByDiff ? ["신상품"] : []),
    ...(product.isPb ? ["PB 상품"] : []),
  ];
  const barcodeText = product.barcode ? `, 바코드 ${product.barcode}` : "";
  return `CU 크롤링 데이터에서 확인된 ${labels.join("/")}이에요. 가격 ${product.price || "미확인"}원${barcodeText}.`;
}

async function seedCuProductCommunityPosts(crawledAt) {
  const authorId = seedUserIds.ai1.toString();
  await Post.updateMany(
    { authorId: "cu-crawler" },
    {
      $set: {
        authorId,
        authorNickname: "CU 상품봇",
      },
    }
  );

  const products = await CuProduct.find({
    $or: [{ isNewFlag: true }, { isNewByDiff: true }, { isPb: true }],
    imageUrl: { $ne: null },
  })
    .sort({ isNewFlag: -1, isPb: -1, lastSeenAt: -1 })
    .limit(12)
    .lean();

  let created = 0;
  for (const [index, product] of products.entries()) {
    const existing = await Post.findOne({
      authorId,
      title: product.name,
    });
    if (existing) continue;

    const price = parseCuPriceToNumber(product.price);
    await Post.create({
      authorId,
      authorNickname: "CU 상품봇",
      authorProfileImageUrl: null,
      title: product.name,
      content: cuProductPostContent(product),
      priceMin: price,
      priceMax: price,
      categories: [
        ...(product.isNewFlag || product.isNewByDiff ? ["트렌드"] : []),
        ...(product.isPb ? ["가성비"] : []),
        "시간절약",
      ],
      likes: Math.max(0, 8 - index),
      dislikes: index % 5 === 0 ? 1 : 0,
      comments: [],
      reviews: [],
      calories: null,
      rating: 0,
      imageData: null,
      imageUrl: product.imageUrl || null,
      imageDatas: [],
      imageUrls: product.imageUrl ? [product.imageUrl] : [],
      details: {
        eatingSteps: ["CU 수집 데이터 기반 상품이라 조합 후보로 바로 참고할 수 있어요."],
        tips: ["신상품/PB 표시는 CU 크롤링 DB에 있는 상품명과 매칭될 때만 붙어요."],
        cautions: [],
        situationTags: [
          ...(product.isNewFlag || product.isNewByDiff ? ["CU 신상품"] : []),
          ...(product.isPb ? ["PB 상품"] : []),
        ],
        reviewPoints: [],
        prepTimeTag: "",
      },
      createdAt: new Date(crawledAt.getTime() - index * 60 * 1000),
      updatedAt: crawledAt,
    });
    created += 1;
  }

  return created;
}

function scheduleCuProductRefresh() {
  if (!CU_AUTO_CRAWL_ENABLED) return;

  const run = async () => {
    try {
      const result = await refreshCuProducts();
      console.log(
        `CU product crawl complete: ${result.total} products, ${result.newCount} new, ${result.pbCount} PB`
      );
    } catch (error) {
      console.error("CU product crawl failed:", error);
    }
  };

  setTimeout(run, 5000);
  setInterval(run, CU_CRAWL_INTERVAL_HOURS * 60 * 60 * 1000);
}

const CONVENIENCE_BROWSER_UA = CU_BROWSER_UA;
const CONVENIENCE_MAX_PAGES_PER_SOURCE = Number(process.env.CONVENIENCE_MAX_PAGES_PER_SOURCE || 20);
const STORE_COLORS = {
  CU: "#652F8F",
  emart24: "#F05A28",
  GS25: "#1C75BC",
  "7-Eleven": "#008061",
};

function absoluteUrl(baseUrl, value) {
  const source = String(value || "").trim();
  if (!source) return null;
  try {
    return new URL(source, baseUrl).toString();
  } catch (_) {
    return source;
  }
}

function extractBarcodeFromImageUrl(imageUrl) {
  const match = String(imageUrl || "").match(/(?:GD_)?([0-9]{8,14})(?:\D|$)/i);
  return match ? match[1] : null;
}

function createConvenienceProductId(store, productId, barcode, name, sourcePage = "") {
  const seed = [store, productId || "", barcode || "", normalizeName(name), sourcePage].join("|");
  return `${String(store).toLowerCase().replace(/[^0-9a-z]+/gi, "-")}-${crypto
    .createHash("sha1")
    .update(seed)
    .digest("hex")
    .slice(0, 16)}`;
}

function normalizePriceText(value) {
  return decodeHtmlText(String(value || "").replace(/<[^>]+>/g, " "));
}

async function fetchPublicHtml(url, { method = "GET", body = null, referer = null } = {}) {
  const response = await fetch(url, {
    method,
    headers: {
      "User-Agent": CONVENIENCE_BROWSER_UA,
      Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      ...(referer ? { Referer: referer } : {}),
      ...(method === "POST" ? { "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8" } : {}),
    },
    body,
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) {
    throw new Error(`${url} failed with status ${response.status}`);
  }
  return response.text();
}

function parseEmart24Products(html, { pathName, isPb = false }) {
  const products = [];
  const blocks = String(html || "").split(/<div\b[^>]*class=["'][^"']*\bitemWrap\b[^"']*["'][^>]*>/i).slice(1);
  for (const block of blocks) {
    const imageUrl = absoluteUrl(
      "https://emart24.co.kr",
      block.match(/<img\b[^>]*src=["']([^"']+)["'][^>]*>/i)?.[1] || ""
    );
    const name = decodeHtmlText(
      block.match(/<div\b[^>]*class=["'][^"']*\bitemtitle\b[^"']*["'][^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/i)?.[1] || ""
    );
    if (!name) continue;
    const price = normalizePriceText(
      block.match(/class=["'][^"']*\bprice\b[^"']*["'][^>]*>([\s\S]*?)<\/a>/i)?.[1] || ""
    );
    const newSpanMatch = block.match(/<span\b(?=[^>]*class=["'][^"']*\bfloatL\b)([^>]*)>\s*NEW\s*<\/span>/i);
    const isVisibleNew = Boolean(newSpanMatch && !/opacity:\s*0/i.test(newSpanMatch[1] || ""));
    const barcode = extractBarcodeFromImageUrl(imageUrl);
    products.push({
      store: "emart24",
      productId: barcode,
      name,
      normalizedName: normalizeName(name),
      price,
      imageUrl,
      barcode,
      isNewFlag: isVisibleNew,
      isPb,
      tags: [
        ...(isVisibleNew ? ["신상품"] : []),
        ...(isPb ? ["PB"] : []),
      ],
      sourcePage: `https://emart24.co.kr/goods/${pathName}`,
      rawText: decodeHtmlText(block.replace(/<[^>]+>/g, " ")),
    });
  }
  return products;
}

function parseSevenElevenProducts(html, { tabLabel = "", isPb = false }) {
  const products = [];
  const blocks = String(html || "").split(/<li>\s*<ul\b[^>]*class=["']tag_list_01["'][^>]*>/i).slice(1);
  for (const block of blocks) {
    const productId = block.match(/fncGoView\('([^']+)'\)/i)?.[1] || null;
    const imageMatch = block.match(/<img\b[^>]*src=["']([^"']+)["'][^>]*alt=["']([^"']*)["'][^>]*>/i);
    const name = decodeHtmlText(imageMatch?.[2] || "");
    if (!name || name.includes("상품 준비중")) continue;
    const imageUrl = absoluteUrl("https://m.7-eleven.co.kr/product/productList.asp", imageMatch?.[1] || "");
    const tags = Array.from(block.matchAll(/<li\b[^>]*>([\s\S]*?)<\/li>/gi))
      .map((match) => decodeHtmlText(match[1].replace(/<[^>]+>/g, " ")))
      .filter((tag) => tag && !["APP", "MAP", "EVENT"].includes(tag));
    const isNewFlag = tags.includes("신상품");
    const pbFlag = isPb || tags.includes("PB") || /^PB\)/i.test(name);
    products.push({
      store: "7-Eleven",
      productId,
      name,
      normalizedName: normalizeName(name),
      price: "",
      imageUrl,
      barcode: null,
      isNewFlag,
      isPb: pbFlag,
      tags: [...new Set([tabLabel, ...tags, ...(isNewFlag ? ["신상품"] : []), ...(pbFlag ? ["PB"] : [])].filter(Boolean))],
      sourcePage: "https://m.7-eleven.co.kr/product/productList.asp",
      rawText: decodeHtmlText(block.replace(/<[^>]+>/g, " ")),
    });
  }
  return products;
}

function parseGs25Products(html, { sourcePage, isPb = false }) {
  const products = [];
  const blocks = String(html || "").split(/<div\b[^>]*class=["']prod_box["'][^>]*>/i).slice(1);
  for (const block of blocks) {
    const imageMatch = block.match(/<img\b[^>]*src=["']([^"']+)["'][^>]*alt=["']([^"']*)["'][^>]*>/i);
    const imageUrl = absoluteUrl("https://gs25.gsretail.com", imageMatch?.[1] || "");
    const name = decodeHtmlText(
      block.match(/<p\b[^>]*class=["']tit["'][^>]*>([\s\S]*?)<\/p>/i)?.[1] || imageMatch?.[2] || ""
    );
    if (!name) continue;
    const price = normalizePriceText(block.match(/<span\b[^>]*class=["']cost["'][^>]*>([\s\S]*?)<\/span>/i)?.[1] || "");
    const tags = Array.from(block.matchAll(/<p\b[^>]*class=["']flg[^"']*["'][^>]*>\s*<span>([\s\S]*?)<\/span>/gi))
      .map((match) => decodeHtmlText(match[1]))
      .filter(Boolean);
    const isNewFlag = tags.includes("NEW");
    const barcode = extractBarcodeFromImageUrl(imageUrl);
    products.push({
      store: "GS25",
      productId: barcode || null,
      name,
      normalizedName: normalizeName(name),
      price,
      imageUrl,
      barcode,
      isNewFlag,
      isPb,
      tags: [...new Set([...tags, ...(isNewFlag ? ["신상품"] : []), ...(isPb ? ["PB"] : [])])],
      sourcePage,
      rawText: decodeHtmlText(block.replace(/<[^>]+>/g, " ")),
    });
  }
  return products;
}

function mergeConvenienceProducts(products) {
  const merged = new Map();
  for (const product of products) {
    const key = `${product.store}|${product.barcode || product.productId || product.normalizedName}`;
    const previous = merged.get(key);
    merged.set(key, {
      ...(previous || {}),
      ...product,
      isNewFlag: Boolean(previous?.isNewFlag || product.isNewFlag),
      isPb: Boolean(previous?.isPb || product.isPb),
      tags: [...new Set([...(previous?.tags || []), ...(product.tags || [])])],
    });
  }
  return Array.from(merged.values());
}

async function crawlEmart24Products() {
  const products = [];
  for (const source of [
    { pathName: "pl", isPb: true },
    { pathName: "event", isPb: false },
    { pathName: "ff", isPb: false },
  ]) {
    for (let page = 1; page <= CONVENIENCE_MAX_PAGES_PER_SOURCE; page += 1) {
      const html = await fetchPublicHtml(
        `https://emart24.co.kr/goods/${source.pathName}?search=&page=${page}&category_seq=&align=`
      );
      const pageProducts = parseEmart24Products(html, source);
      if (pageProducts.length === 0) break;
      products.push(...pageProducts);
    }
  }
  return products;
}

async function crawlSevenElevenProducts() {
  const products = [];
  const mainHtml = await fetchPublicHtml("https://m.7-eleven.co.kr/product/productList.asp");
  products.push(...parseSevenElevenProducts(mainHtml, { tabLabel: "1+1" }));
  const tabs = [
    ["4", "할인행사", false],
    ["5", "PB상품", true],
    ["6", "인기상품", false],
  ];
  for (const [pTab, tabLabel, isPb] of tabs) {
    for (let page = 1; page <= Math.min(CONVENIENCE_MAX_PAGES_PER_SOURCE, 12); page += 1) {
      const body = new URLSearchParams({
        intPageSize: "20",
        intCurrPage: String(page),
        pTab,
      }).toString();
      const html = await fetchPublicHtml("https://m.7-eleven.co.kr/product/plistMoreAjax.asp", {
        method: "POST",
        referer: "https://m.7-eleven.co.kr/product/productList.asp",
        body,
      });
      const pageProducts = parseSevenElevenProducts(html, { tabLabel, isPb });
      if (pageProducts.length === 0) break;
      products.push(...pageProducts);
    }
  }
  return products;
}

async function crawlGs25Products() {
  const products = [];
  const sources = [
    { url: "https://gs25.gsretail.com/gscvs/ko/products/event-goods", isPb: false },
    { url: "https://gs25.gsretail.com/gscvs/ko/products/youus-main", isPb: true },
    { url: "https://gs25.gsretail.com/gscvs/ko/products/youus-freshfood", isPb: true },
  ];
  for (const source of sources) {
    const html = await fetchPublicHtml(source.url);
    products.push(...parseGs25Products(html, { sourcePage: source.url, isPb: source.isPb }));
  }
  return products;
}

async function crawlConvenienceProducts() {
  const results = [];
  const errors = [];
  for (const source of [
    ["emart24", crawlEmart24Products],
    ["7-Eleven", crawlSevenElevenProducts],
    ["GS25", crawlGs25Products],
  ]) {
    try {
      const products = await source[1]();
      results.push(...products);
    } catch (error) {
      errors.push({ source: source[0], message: String(error.message || error) });
    }
  }
  return { products: mergeConvenienceProducts(results), errors };
}

function serializeConvenienceProduct(product) {
  return {
    id: product.id,
    store: product.store,
    productId: product.productId || null,
    name: product.name,
    price: product.price || "",
    imageUrl: product.imageUrl || null,
    barcode: product.barcode || null,
    isNewFlag: Boolean(product.isNewFlag || product.isNewByDiff),
    siteNewFlag: Boolean(product.isNewFlag),
    diffNewFlag: Boolean(product.isNewByDiff),
    isPb: Boolean(product.isPb),
    tags: product.tags || [],
    sourcePage: product.sourcePage || "",
    color: STORE_COLORS[product.store] || "#273342",
    firstSeenAt: product.firstSeenAt,
    lastSeenAt: product.lastSeenAt,
    lastCrawledAt: product.lastCrawledAt,
  };
}

async function refreshConvenienceProducts() {
  const crawledAt = new Date();
  const existingCount = await ConvenienceProduct.estimatedDocumentCount();
  const { products, errors } = await crawlConvenienceProducts();
  let inserted = 0;
  let updated = 0;
  let barcodeCount = 0;
  let newCount = 0;
  let pbCount = 0;

  for (const product of products) {
    const id = createConvenienceProductId(
      product.store,
      product.productId,
      product.barcode,
      product.name,
      product.sourcePage
    );
    const existing = await ConvenienceProduct.findOne({ id });
    const isNewByDiff = existingCount > 0 && !existing;
    const isNewFlag = Boolean(product.isNewFlag || isNewByDiff);
    if (product.barcode) barcodeCount += 1;
    if (isNewFlag) newCount += 1;
    if (product.isPb) pbCount += 1;

    await ConvenienceProduct.findOneAndUpdate(
      { id },
      {
        $set: {
          ...product,
          id,
          normalizedName: product.normalizedName || normalizeName(product.name),
          isNewFlag,
          isNewByDiff,
          lastSeenAt: crawledAt,
          lastCrawledAt: crawledAt,
        },
        $setOnInsert: { firstSeenAt: crawledAt },
      },
      { upsert: true, returnDocument: "after", setDefaultsOnInsert: true }
    );
    if (existing) updated += 1;
    else inserted += 1;
  }

  const seededPosts = await seedConvenienceProductCommunityPosts(crawledAt);
  return {
    crawledAt,
    total: products.length,
    inserted,
    updated,
    barcodeCount,
    newCount,
    pbCount,
    seededPosts,
    errors,
  };
}

function convenienceProductPostContent(product) {
  const labels = [
    ...(product.isNewFlag || product.isNewByDiff ? ["신상품"] : []),
    ...(product.isPb ? ["PB 상품"] : []),
  ];
  const barcodeText = product.barcode ? `, 바코드 ${product.barcode}` : "";
  return `${product.store} 공개 상품 데이터에서 확인된 ${labels.join("/") || "편의점 상품"}이에요. 가격 ${product.price || "미확인"}${barcodeText}.`;
}

async function seedConvenienceProductCommunityPosts(crawledAt) {
  const storeAuthors = {
    emart24: { id: seedUserIds.ai2.toString(), nickname: "emart24 상품봇" },
    GS25: { id: seedUserIds.ai3.toString(), nickname: "GS25 상품봇" },
    "7-Eleven": { id: seedUserIds.ai4.toString(), nickname: "7-Eleven 상품봇" },
  };
  const products = await ConvenienceProduct.find({
    $or: [{ isNewFlag: true }, { isNewByDiff: true }, { isPb: true }],
    imageUrl: { $ne: null },
  })
    .sort({ isNewFlag: -1, isPb: -1, lastSeenAt: -1 })
    .limit(18)
    .lean();

  let created = 0;
  for (const [index, product] of products.entries()) {
    const author = storeAuthors[product.store] || storeAuthors.emart24;
    const existing = await Post.findOne({ authorId: author.id, title: product.name });
    if (existing) continue;
    const price = parseCuPriceToNumber(product.price);
    await Post.create({
      authorId: author.id,
      authorNickname: author.nickname,
      authorProfileImageUrl: null,
      title: product.name,
      content: convenienceProductPostContent(product),
      priceMin: price,
      priceMax: price,
      categories: [
        ...(product.isNewFlag || product.isNewByDiff ? ["트렌드"] : []),
        ...(product.isPb ? ["가성비"] : []),
        "시간절약",
      ],
      likes: Math.max(0, 7 - (index % 8)),
      dislikes: index % 6 === 0 ? 1 : 0,
      comments: [],
      reviews: [],
      calories: null,
      rating: 0,
      imageData: null,
      imageUrl: product.imageUrl || null,
      imageDatas: [],
      imageUrls: product.imageUrl ? [product.imageUrl] : [],
      details: {
        eatingSteps: [`${product.store} 공개 상품 데이터 기반으로 가져온 상품이에요.`],
        tips: ["신상품/PB 표시는 편의점 상품 DB에 있는 상품명과 매칭될 때만 붙어요."],
        cautions: [],
        situationTags: [
          ...(product.isNewFlag || product.isNewByDiff ? [`${product.store} 신상품`] : []),
          ...(product.isPb ? [`${product.store} PB`] : []),
        ],
        reviewPoints: [],
        prepTimeTag: "",
      },
      createdAt: new Date(crawledAt.getTime() - index * 70 * 1000),
      updatedAt: crawledAt,
    });
    created += 1;
  }
  return created;
}

async function refreshTopFiveBadges() {
  const ranked = (await Post.find({})).filter(qualifiesForPopularBadge).sort((a, b) => {
    const likeCompare = Number(b.likes || 0) - Number(a.likes || 0);
    if (likeCompare !== 0) return likeCompare;
    return new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime();
  }).slice(0, 5);
  const ids = new Set(ranked.map((post) => post._id.toString()));
  const worstRanked = (await Post.find({})).filter(qualifiesForWorstBadge).sort((a, b) => {
    const dislikeCompare = Number(b.dislikes || 0) - Number(a.dislikes || 0);
    if (dislikeCompare !== 0) return dislikeCompare;
    const ratioA = dislikeRatio(a);
    const ratioB = dislikeRatio(b);
    if (ratioA !== ratioB) return ratioB - ratioA;
    return new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime();
  }).slice(0, 5);
  const worstIds = new Set(worstRanked.map((post) => post._id.toString()));
  const now = new Date();
  const posts = await Post.find({});

  await Promise.all(
    posts.map(async (post) => {
      if (ids.has(post._id.toString()) && !post.topFiveEnteredAt) {
        post.topFiveEnteredAt = now;
      }
      if (!ids.has(post._id.toString()) && post.topFiveEnteredAt) {
        post.topFiveEnteredAt = null;
      }
      if (worstIds.has(post._id.toString()) && !post.topWorstEnteredAt) {
        post.topWorstEnteredAt = now;
      }
      if (!worstIds.has(post._id.toString()) && post.topWorstEnteredAt) {
        post.topWorstEnteredAt = null;
      }
      await post.save();
    })
  );
}

function qualifiesForPopularBadge(post) {
  const likes = Number(post.likes || 0);
  const dislikes = Number(post.dislikes || 0);
  if (likes < 10) return false;
  return likes >= Math.max(1, dislikes * 3);
}

function dislikeRatio(post) {
  const likes = Number(post.likes || 0);
  const dislikes = Number(post.dislikes || 0);
  const total = likes + dislikes;
  return total <= 0 ? 0 : dislikes / total;
}

function qualifiesForWorstBadge(post) {
  const likes = Number(post.likes || 0);
  const dislikes = Number(post.dislikes || 0);
  if (dislikes < 8) return false;
  return dislikeRatio(post) >= 0.45 || dislikes >= likes;
}

async function backfillLegacyPosts() {
  const posts = await Post.find({}).sort({ createdAt: 1 });
  const sampleDislikes = {
    "딸기우유 프레첼 한입 조합": 2,
    "불닭삼각김밥 + 쿨피스 리셋 조합": 1,
    "요거트 + 컵과일 상큼 디저트": 4,
    "참치마요 김밥 + 청양마요 소스": 5,
    "얼음컵 아메리카노 + 초코바삭롤": 1,
    "닭가슴살볼 + 구운계란 든든 조합": 3,
    "레몬탄산수 + 새우칩 상큼짭짤": 6,
    "쫀득빵 + 바닐라우유 야식 조합": 2,
  };
  let aiIndex = 1;
  const legacyAiNames = new Set(["민지", "현우", "수빈", "지호", "다은", "준서", "예린", "도윤"]);
  for (const post of posts) {
    let changed = false;
    if (
      !post.authorId ||
      !post.authorNickname ||
      post.authorNickname === "편pick" ||
      String(post.authorId).startsWith("seed-author-") ||
      String(post.authorId).startsWith("legacy-ai-") ||
      legacyAiNames.has(post.authorNickname)
    ) {
      post.authorId = `legacy-ai-${aiIndex}`;
      post.authorNickname = `ai${aiIndex}`;
      aiIndex += 1;
      changed = true;
    }
    if (post.dislikes == null) {
      post.dislikes = 0;
      changed = true;
    }
    if (
      post.dislikes === 0 &&
      String(post.authorNickname).startsWith("ai") &&
      sampleDislikes[post.title] != null
    ) {
      post.dislikes = sampleDislikes[post.title];
      changed = true;
    }
    if (post.dislikedByMe == null) {
      post.dislikedByMe = false;
      changed = true;
    }
    if (post.topWorstEnteredAt === undefined) {
      post.topWorstEnteredAt = null;
      changed = true;
    }
    if (changed) {
      await post.save();
    }
  }
}

async function backfillLegacyProducts() {
  const products = await Product.find({});
  for (const product of products) {
    let changed = false;

    if (!product.normalizedName && product.officialName) {
      product.normalizedName = normalizeName(product.officialName);
      changed = true;
    }
    if (!Array.isArray(product.categories)) {
      product.categories = [];
      changed = true;
    }
    if (!product.images || typeof product.images !== "object") {
      product.images = { product: null, meta: null };
      changed = true;
    }
    if (!Array.isArray(product.searchTokens) || product.searchTokens.length === 0) {
      product.searchTokens = buildSearchTokens(product);
      changed = true;
    }
    if (!Array.isArray(product.sources) || product.sources.length === 0) {
      product.sources = [toSourceEntry(product)];
      changed = true;
    }
    if (!product.verificationStatus) {
      product.verificationStatus = product.source === "haccp-public-data" ? "official-public" : "auto-imported";
      changed = true;
    }
    if (!product.lookupCount) {
      product.lookupCount = 1;
      changed = true;
    }

    if (changed) {
      await product.save();
    }
  }
}

async function seedIfNeeded() {
  if ((await User.countDocuments()) === 0) {
    await User.insertMany(seedUsers);
  }
  if ((await Post.countDocuments()) > 0) return;
  await Post.insertMany(seedPosts);
  await refreshTopFiveBadges();
}

async function resetDemoDataIfRequested() {
  if (process.env.RESET_DEMO_DATA !== "true") {
    return;
  }
  await Post.deleteMany({});
  await User.deleteMany({});
}

app.post("/api/auth/signup", async (req, res) => {
  const username = String(req.body.username || "").trim();
  const nickname = String(req.body.nickname || "").trim();
  const password = String(req.body.password || "");

  if (!username || !nickname || !password) {
    return res.status(400).json({ message: "닉네임, 아이디, 비밀번호를 모두 입력해 주세요." });
  }

  if (await User.findOne({ username })) {
    return res.status(409).json({ message: "이미 사용 중인 아이디예요." });
  }
  if (await User.findOne({ nickname })) {
    return res.status(409).json({ message: "이미 사용 중인 닉네임이에요." });
  }

  const user = await User.create({
    username,
    nickname,
    passwordHash: hashPassword(password),
  });

  return res.status(201).json({
    user: await serializeUser(user),
    token: createAuthToken(user),
  });
});

app.post("/api/auth/signin", async (req, res) => {
  const loginKey = String(req.body.username || "").trim();
  const password = String(req.body.password || "");

  if (!loginKey || !password) {
    return res.status(400).json({ message: "아이디 또는 닉네임과 비밀번호를 입력해 주세요." });
  }

  const user = await User.findOne({
    $or: [{ username: loginKey }, { nickname: loginKey }],
  });

  if (!user || !passwordMatches(password, user.passwordHash)) {
    return res.status(401).json({ message: "아이디 또는 비밀번호가 맞지 않아요." });
  }

  if (!String(user.passwordHash).startsWith("$2")) {
    user.passwordHash = hashPassword(password);
    await user.save();
  }

  return res.json({
    user: await serializeUser(user),
    token: createAuthToken(user),
  });
});

app.post("/api/bot/analyze", requireAuth, async (req, res) => {
  const prompt = String(req.body.prompt || "").trim();
  const memoryNotes = Array.isArray(req.body.memoryNotes)
    ? req.body.memoryNotes.map(String).slice(0, 6)
    : [];
  if (!prompt) {
    return res.status(400).json({ message: "분석할 문장이 필요해요." });
  }
  const localAnalysis = analyzeBotPromptLocally(prompt);
  if (!OPENAI_API_KEY) {
    return res.json({ analysis: localAnalysis, source: "local-fallback" });
  }

  try {
    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${OPENAI_API_KEY}`,
      },
      body: JSON.stringify({
        model: OPENAI_BOT_MODEL,
        input: [
          {
            role: "developer",
            content: [
              {
                type: "input_text",
                text:
                  "You analyze Korean convenience-store recommendation requests. Extract only facts supported by the user's message. Never choose products. Budget is KRW. timeAvailableMinutes is preparation/selection time. wantedTastes must use only 달달, 매콤, 새콤, 짭짤. emotion must be one of neutral, happy, excited, relieved, sad, lonely, angry, stressed, anxious, nervous, tired, sick. Keep summary to one empathetic Korean sentence.",
              },
            ],
          },
          {
            role: "user",
            content: [
              {
                type: "input_text",
                text: `최근 기억: ${memoryNotes.join(" | ") || "없음"}\n현재 요청: ${prompt}`,
              },
            ],
          },
        ],
        text: {
          format: {
            type: "json_schema",
            name: "pyeonpick_situation",
            strict: true,
            schema: {
              type: "object",
              additionalProperties: false,
              properties: {
                emotion: {
                  type: "string",
                  enum: [
                    "neutral",
                    "happy",
                    "excited",
                    "relieved",
                    "sad",
                    "lonely",
                    "angry",
                    "stressed",
                    "anxious",
                    "nervous",
                    "tired",
                    "sick",
                  ],
                },
                budget: { type: ["integer", "null"] },
                timeAvailableMinutes: { type: ["integer", "null"] },
                lateNight: { type: "boolean" },
                mealPurpose: { type: ["string", "null"] },
                bodyCondition: { type: ["string", "null"] },
                wantedTastes: {
                  type: "array",
                  items: {
                    type: "string",
                    enum: ["달달", "매콤", "새콤", "짭짤"],
                  },
                },
                avoidConditions: {
                  type: "array",
                  items: { type: "string" },
                },
                summary: { type: "string" },
              },
              required: [
                "emotion",
                "budget",
                "timeAvailableMinutes",
                "lateNight",
                "mealPurpose",
                "bodyCondition",
                "wantedTastes",
                "avoidConditions",
                "summary",
              ],
            },
          },
        },
      }),
      signal: AbortSignal.timeout(4000),
    });

    if (!response.ok) {
      return res.json({ analysis: localAnalysis, source: "local-fallback" });
    }
    const payload = await response.json();
    const analysis = tryParseJsonObject(extractResponsesText(payload));
    if (!analysis) {
      return res.json({ analysis: localAnalysis, source: "local-fallback" });
    }
    return res.json({ analysis, source: "openai" });
  } catch (_) {
    return res.json({ analysis: localAnalysis, source: "local-fallback" });
  }
});

app.get("/api/users/:id", requireAuth, requireSelf, async (req, res) => {
  const user = await User.findById(req.params.id);
  if (!user) {
    return res.status(404).json({ message: "사용자를 찾을 수 없어요." });
  }

  return res.json({ user: await serializeUser(user) });
});

app.put("/api/users/:id", requireAuth, requireSelf, async (req, res) => {
  const user = await User.findById(req.params.id);
  if (!user) {
    return res.status(404).json({ message: "사용자를 찾을 수 없어요." });
  }

  user.nickname = String(req.body.nickname || user.nickname).trim();
  user.profileImageUrl = req.body.profileImageUrl ?? null;
  user.botSetup = req.body.botSetup ?? null;
  user.memoryNotes = Array.isArray(req.body.memoryNotes) ? req.body.memoryNotes : [];
  user.botMessages = Array.isArray(req.body.botMessages) ? req.body.botMessages : [];
  user.archivedConversations = Array.isArray(req.body.archivedConversations) ? req.body.archivedConversations : [];
  user.likedPostIds = Array.isArray(req.body.likedPostIds) ? req.body.likedPostIds : (user.likedPostIds || []);
  user.dislikedPostIds = Array.isArray(req.body.dislikedPostIds) ? req.body.dislikedPostIds : (user.dislikedPostIds || []);
  user.savedPostIds = Array.isArray(req.body.savedPostIds) ? req.body.savedPostIds : (user.savedPostIds || []);
  user.pickedAuthorIds = Array.isArray(req.body.pickedAuthorIds) ? req.body.pickedAuthorIds : (user.pickedAuthorIds || []);
  user.battleState = req.body.battleState || user.battleState || {};
  user.profilePublic = req.body.profilePublic == null ? (user.profilePublic !== false) : Boolean(req.body.profilePublic);
  user.profileVisibility = req.body.profileVisibility || user.profileVisibility || {};

  await user.save();
  return res.json({ user: await serializeUser(user) });
});

app.get("/api/image-proxy", async (req, res) => {
  const rawUrl = String(req.query.url || "").trim();
  if (!/^https?:\/\//i.test(rawUrl)) {
    return res.status(400).send("Invalid image URL");
  }

  try {
    const upstream = await fetch(rawUrl, {
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36",
        Accept: "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
      },
      signal: AbortSignal.timeout(8000),
    });

    if (!upstream.ok) {
      return res.status(502).send("Image upstream error");
    }

    const contentType = upstream.headers.get("content-type") || "image/jpeg";
    if (!contentType.toLowerCase().startsWith("image/")) {
      return res.status(415).send("URL is not an image");
    }

    const buffer = Buffer.from(await upstream.arrayBuffer());
    res.setHeader("Content-Type", contentType);
    res.setHeader("Cache-Control", "public, max-age=86400");
    res.setHeader("Access-Control-Allow-Origin", "*");
    return res.send(buffer);
  } catch (_) {
    return res.status(502).send("Image proxy failed");
  }
});

app.get("/api/posts", async (req, res) => {
  const {
    query = "",
    minPrice,
    maxPrice,
    sort = "latest",
    viewerId,
    cursor,
    limit,
    tags = "",
    likedGenderMajority = "",
  } = req.query;
  const filters = {};

  if (query) {
    if (String(query).startsWith("#")) {
      filters.categories = { $regex: String(query).slice(1), $options: "i" };
    } else {
      filters.title = { $regex: String(query), $options: "i" };
    }
  }

  const requestedTags = String(tags)
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean);
  if (requestedTags.length > 0) {
    filters.$and = filters.$and || [];
    for (const tag of requestedTags) {
      filters.$and.push({
        categories: { $regex: tag, $options: "i" },
      });
    }
  }

  if (minPrice || maxPrice) {
    filters.$and = filters.$and || [];
    if (minPrice) filters.$and.push({ priceMax: { $gte: Number(minPrice) } });
    if (maxPrice) filters.$and.push({ priceMin: { $lte: Number(maxPrice) } });
    if (filters.$and.length === 0) delete filters.$and;
  }

  if (["male", "female"].includes(String(likedGenderMajority))) {
    const usersWithGender = await User.find({
      "botSetup.gender": { $in: ["남자", "여자"] },
      likedPostIds: { $exists: true, $ne: [] },
    })
      .select("botSetup.gender likedPostIds")
      .lean();
    const audienceByPost = new Map();

    for (const user of usersWithGender) {
      const key = user.botSetup?.gender === "남자" ? "male" : "female";
      for (const postId of new Set((user.likedPostIds || []).map(String))) {
        if (!mongoose.Types.ObjectId.isValid(postId)) continue;
        const counts = audienceByPost.get(postId) || { male: 0, female: 0 };
        counts[key] += 1;
        audienceByPost.set(postId, counts);
      }
    }

    const matchingPostIds = Array.from(audienceByPost.entries())
      .filter(([, counts]) => counts[likedGenderMajority] > counts[likedGenderMajority === "male" ? "female" : "male"])
      .map(([postId]) => postId);
    filters._id = { $in: matchingPostIds };
  }

  const cursorPayload = cursor ? decodePostCursor(cursor) : null;
  const cursorFilter = buildPostCursorFilter(String(sort), cursorPayload);
  if (cursorFilter) {
    filters.$and = [...(filters.$and || []), cursorFilter];
  }

  const sortOption = sort === "popular"
    ? { likes: -1, createdAt: -1 }
    : sort === "worst"
        ? { dislikes: -1, createdAt: -1 }
        : { createdAt: -1 };
  const pageSize = Math.min(Math.max(Number(limit) || 6, 1), 20);
  const posts = await Post.find(filters).sort({ ...sortOption, _id: -1 }).limit(pageSize + 1);
  const currentUser = viewerId ? await findUserByIdLeanOrNull(viewerId) : null;
  const hasMore = posts.length > pageSize;
  const pagePosts = hasMore ? posts.slice(0, pageSize) : posts;
  await hydratePostAuthorImages(pagePosts);
  const nextCursor = hasMore && pagePosts.length > 0
    ? encodePostCursor(pagePosts[pagePosts.length - 1], String(sort))
    : null;
  res.json({
    posts: pagePosts.map((post) => serializePost(post, currentUser)),
    hasMore,
    nextCursor,
  });
});

app.get("/api/posts/catalog", async (req, res) => {
  const viewerId = String(req.query.viewerId || "").trim();
  const currentUser = viewerId ? await findUserByIdLeanOrNull(viewerId) : null;
  const posts = await Post.find({})
    .select(
      "authorId authorNickname authorProfileImageUrl title content priceMin priceMax categories likes dislikes comments reviews calories rating createdAt imageData imageUrl imageDatas imageUrls details topFiveEnteredAt topWorstEnteredAt"
    )
    .sort({ createdAt: -1, _id: -1 })
    .limit(1000);
  await hydratePostAuthorImages(posts);
  return res.json({
    posts: posts.map((post) => serializePostCatalog(post, currentUser, req)),
  });
});

app.get("/api/posts/feature-index", async (req, res) => {
  const posts = await Post.find({})
    .select("authorId title likes dislikes comments reviews likeEvents createdAt topFiveEnteredAt topWorstEnteredAt")
    .sort({ createdAt: -1, _id: -1 })
    .limit(1000);

  res.json({
    posts: posts.map(serializePostFeatureInfo),
  });
});

app.get("/api/posts/:id/images/:index", async (req, res) => {
  const post = await Post.findById(req.params.id)
    .select("imageData imageDatas")
    .lean();
  if (!post) return res.status(404).send("Post not found");

  const images = post.imageDatas && post.imageDatas.length > 0
    ? post.imageDatas
    : (post.imageData ? [post.imageData] : []);
  const rawImage = images[Number(req.params.index)];
  if (!rawImage) return res.status(404).send("Image not found");

  const dataUrlMatch = String(rawImage).match(/^data:([^;]+);base64,(.+)$/s);
  const mimeType = dataUrlMatch?.[1] || "image/jpeg";
  const base64 = dataUrlMatch?.[2] || String(rawImage).split(",").pop();
  try {
    const imageBuffer = Buffer.from(base64, "base64");
    res.setHeader("Content-Type", mimeType);
    res.setHeader("Cache-Control", "public, max-age=86400");
    return res.send(imageBuffer);
  } catch (_) {
    return res.status(415).send("Invalid image data");
  }
});

app.get("/api/posts/:id/audience", async (req, res) => {
  const postId = String(req.params.id || "");
  if (!mongoose.Types.ObjectId.isValid(postId)) {
    return res.status(400).json({ message: "게시글 정보가 올바르지 않아요." });
  }
  if (!(await Post.exists({ _id: postId }))) {
    return res.status(404).json({ message: "게시글을 찾을 수 없어요." });
  }

  const users = await User.find({
    likedPostIds: postId,
    "botSetup.gender": { $in: ["남자", "여자"] },
  })
    .select("botSetup.gender")
    .lean();
  const maleCount = users.filter((user) => user.botSetup?.gender === "남자").length;
  const femaleCount = users.filter((user) => user.botSetup?.gender === "여자").length;
  return res.json({ maleCount, femaleCount, totalWithGender: maleCount + femaleCount });
});

app.post("/api/posts", async (req, res) => {
  const {
    authorId,
    authorNickname,
    title,
    content,
    priceMin,
    priceMax,
    categories,
    imageData,
    imageUrl,
    imageDatas,
    imageUrls,
    details,
    calories,
    rating,
  } = req.body;
  const normalizedImageDatas = Array.isArray(imageDatas) ? imageDatas.filter(Boolean) : (imageData ? [imageData] : []);
  const normalizedImageUrls = Array.isArray(imageUrls) ? imageUrls.filter(Boolean) : (imageUrl ? [imageUrl] : []);
  const hasImage = normalizedImageDatas.length > 0 || normalizedImageUrls.length > 0;
  const normalizedDetails = details || {};
  const normalizedTitle = String(title || "").trim();
  const normalizedRating = Math.min(5, Math.max(0, Number(rating) || 0));

  if (!hasImage) {
    return res.status(400).json({ message: "사진은 꼭 필요합니다." });
  }
  if (!normalizedTitle) {
    return res.status(400).json({ message: "품명은 꼭 필요합니다." });
  }
  if (normalizedRating <= 0) {
    return res.status(400).json({ message: "평점은 꼭 필요합니다." });
  }
  if (!authorId || !authorNickname) {
    return res.status(400).json({ message: "작성자 정보가 필요합니다." });
  }
  const author = await findUserByIdLeanOrNull(authorId);

  const post = await Post.create({
    authorId,
    authorNickname,
    authorProfileImageUrl: author?.profileImageUrl || null,
    title: normalizedTitle,
    content: content || "",
    priceMin: Math.max(0, Number(priceMin) || 0),
    priceMax: Math.max(0, Number(priceMax) || Number(priceMin) || 0),
    categories: Array.isArray(categories) ? categories : [],
    imageData: normalizedImageDatas[0] || null,
    imageUrl: normalizedImageUrls[0] || null,
    imageDatas: normalizedImageDatas,
    imageUrls: normalizedImageUrls,
    details: normalizedDetails,
    calories: Number.isFinite(Number(calories)) ? Math.max(0, Number(calories)) : null,
    rating: normalizedRating,
    dislikes: 0,
    dislikedByMe: false,
  });

  await refreshTopFiveBadges();
  await hydratePostAuthorImages(post);
  res.status(201).json({ post: serializePost(post) });
});

app.put("/api/posts/:id", async (req, res) => {
  const {
    authorId,
    authorNickname,
    title,
    content,
    priceMin,
    priceMax,
    categories,
    imageData,
    imageUrl,
    imageDatas,
    imageUrls,
    details,
    calories,
    rating,
  } = req.body;
  const normalizedImageDatas = Array.isArray(imageDatas) ? imageDatas.filter(Boolean) : (imageData ? [imageData] : []);
  const normalizedImageUrls = Array.isArray(imageUrls) ? imageUrls.filter(Boolean) : (imageUrl ? [imageUrl] : []);
  const normalizedDetails = details || {};

  const post = await Post.findById(req.params.id);
  if (!post) return res.status(404).json({ message: "게시글을 찾을 수 없습니다." });
  if (!authorId || post.authorId !== authorId) {
    return res.status(403).json({ message: "본인 게시글만 수정할 수 있습니다." });
  }

  const hasImage = normalizedImageDatas.length > 0 || normalizedImageUrls.length > 0 || (post.imageDatas?.length || 0) > 0 || (post.imageUrls?.length || 0) > 0;
  const normalizedTitle = String(title || "").trim();
  const normalizedRating = Math.min(5, Math.max(0, Number(rating) || 0));

  if (!hasImage) {
    return res.status(400).json({ message: "사진은 꼭 필요합니다." });
  }
  if (!normalizedTitle) {
    return res.status(400).json({ message: "품명은 꼭 필요합니다." });
  }
  if (normalizedRating <= 0) {
    return res.status(400).json({ message: "평점은 꼭 필요합니다." });
  }

  post.authorNickname = authorNickname || post.authorNickname;
  if (authorId) {
    const author = await findUserByIdLeanOrNull(authorId);
    post.authorProfileImageUrl = author?.profileImageUrl || post.authorProfileImageUrl || null;
  }
  post.title = normalizedTitle;
  post.content = content || "";
  post.priceMin = Math.max(0, Number(priceMin) || 0);
  post.priceMax = Math.max(0, Number(priceMax) || Number(priceMin) || 0);
  post.categories = Array.isArray(categories) ? categories : [];
  post.imageData = normalizedImageDatas[0] || post.imageData || null;
  post.imageUrl = normalizedImageUrls[0] || post.imageUrl || null;
  post.imageDatas = normalizedImageDatas.length > 0 ? normalizedImageDatas : (post.imageDatas || (post.imageData ? [post.imageData] : []));
  post.imageUrls = normalizedImageUrls.length > 0 ? normalizedImageUrls : (post.imageUrls || (post.imageUrl ? [post.imageUrl] : []));
  post.details = normalizedDetails || post.details || {};
  post.calories = Number.isFinite(Number(calories)) ? Math.max(0, Number(calories)) : null;
  post.rating = normalizedRating;
  await post.save();

  await refreshTopFiveBadges();
  await hydratePostAuthorImages(post);
  res.json({ post: serializePost(post) });
});

app.delete("/api/posts/:id", async (req, res) => {
  const { authorId } = req.query;
  const post = await Post.findById(req.params.id);
  if (!post) return res.status(404).json({ message: "게시글을 찾을 수 없습니다." });
  if (!authorId || post.authorId !== authorId) {
    return res.status(403).json({ message: "본인 게시글만 삭제할 수 있습니다." });
  }

  await Post.findByIdAndDelete(req.params.id);
  await refreshTopFiveBadges();
  res.json({ success: true });
});

app.post("/api/posts/:id/like", async (req, res) => {
  const userId = String(req.body.userId || "");
  if (!userId) return res.status(400).json({ message: "사용자 정보가 필요합니다." });

  const post = await Post.findById(req.params.id);
  if (!post) return res.status(404).json({ message: "게시글을 찾을 수 없습니다." });
  const user = await findUserByIdOrNull(userId);
  if (!user) return res.status(404).json({ message: "사용자를 찾을 수 없습니다." });

  const postId = post._id.toString();
  const likedIndex = (user.likedPostIds || []).findIndex((id) => String(id) == postId);
  const dislikedIndex = (user.dislikedPostIds || []).findIndex((id) => String(id) == postId);

  if (likedIndex >= 0) {
    post.likes = Math.max(0, post.likes - 1);
    post.likeEvents = (post.likeEvents || []).filter(
      (event) => String(event.userId) !== userId
    );
    user.likedPostIds.splice(likedIndex, 1);
  } else {
    post.likes += 1;
    post.likeEvents = [
      ...(post.likeEvents || []).filter(
        (event) => String(event.userId) !== userId
      ),
      { userId, createdAt: new Date() },
    ];
    user.likedPostIds.push(postId);
    if (dislikedIndex >= 0) {
      post.dislikes = Math.max(0, post.dislikes - 1);
      user.dislikedPostIds.splice(dislikedIndex, 1);
    }
  }

  await post.save();
  await user.save();
  await refreshTopFiveBadges();
  await hydratePostAuthorImages(post);
  res.json({ post: serializePost(post, user) });
});

app.post("/api/posts/:id/dislike", async (req, res) => {
  const userId = String(req.body.userId || "");
  if (!userId) return res.status(400).json({ message: "사용자 정보가 필요합니다." });

  const post = await Post.findById(req.params.id);
  if (!post) return res.status(404).json({ message: "게시글을 찾을 수 없습니다." });
  const user = await findUserByIdOrNull(userId);
  if (!user) return res.status(404).json({ message: "사용자를 찾을 수 없습니다." });

  const postId = post._id.toString();
  const dislikedIndex = (user.dislikedPostIds || []).findIndex((id) => String(id) == postId);
  const likedIndex = (user.likedPostIds || []).findIndex((id) => String(id) == postId);

  if (dislikedIndex >= 0) {
    post.dislikes = Math.max(0, post.dislikes - 1);
    user.dislikedPostIds.splice(dislikedIndex, 1);
  } else {
    post.dislikes += 1;
    user.dislikedPostIds.push(postId);
    if (likedIndex >= 0) {
      post.likes = Math.max(0, post.likes - 1);
      post.likeEvents = (post.likeEvents || []).filter(
        (event) => String(event.userId) !== userId
      );
      user.likedPostIds.splice(likedIndex, 1);
    }
  }

  await post.save();
  await user.save();
  await refreshTopFiveBadges();
  await hydratePostAuthorImages(post);
  res.json({ post: serializePost(post, user) });
});

app.post("/api/posts/:id/comments", async (req, res) => {
  const { text, authorId, authorNickname } = req.body;
  if (!text || !String(text).trim()) {
    return res.status(400).json({ message: "댓글 내용을 입력해 주세요." });
  }

  const post = await Post.findById(req.params.id);
  if (!post) return res.status(404).json({ message: "게시글을 찾을 수 없습니다." });
  const author = authorId ? await findUserByIdLeanOrNull(authorId) : null;

  post.comments.push({
    authorId: String(authorId || ""),
    authorNickname: String(authorNickname || "익명"),
    authorProfileImageUrl: author?.profileImageUrl || null,
    text: String(text).trim(),
  });
  await post.save();
  await hydratePostAuthorImages(post);
  res.json({ post: serializePost(post) });
});

app.post("/api/posts/:id/reviews", async (req, res) => {
  const post = await Post.findById(req.params.id);
  if (!post) return res.status(404).json({ message: "게시글을 찾을 수 없습니다." });

  const review = {
    id: String(req.body.id || crypto.randomUUID()),
    authorId: String(req.body.authorId || ""),
    authorNickname: String(req.body.authorNickname || "익명"),
    text: String(req.body.text || "").trim(),
    rating: Math.min(5, Math.max(1, Number(req.body.rating) || 3)),
    tags: Array.isArray(req.body.tags)
      ? req.body.tags.filter((tag) => ["저칼로리", "가성비", "시간절약", "호불호", "트렌드"].includes(tag))
      : [],
    sweet: Math.min(5, Math.max(1, Number(req.body.sweet) || 1)),
    salty: Math.min(5, Math.max(1, Number(req.body.salty) || 1)),
    spicy: Math.min(5, Math.max(1, Number(req.body.spicy) || 1)),
    sour: Math.min(5, Math.max(1, Number(req.body.sour) || 1)),
    caution: String(req.body.caution || "").trim(),
    createdAt: req.body.createdAt ? new Date(req.body.createdAt) : new Date(),
  };
  post.reviews.push(review);
  await post.save();
  await hydratePostAuthorImages(post);
  return res.json({ post: serializePost(post) });
});

app.put("/api/posts/:postId/reviews/:reviewId", async (req, res) => {
  const post = await Post.findById(req.params.postId);
  if (!post) return res.status(404).json({ message: "게시글을 찾을 수 없습니다." });
  const review = post.reviews.find((item) => item.id === req.params.reviewId);
  if (!review) return res.status(404).json({ message: "후기를 찾을 수 없습니다." });
  if (!req.body.authorId || review.authorId !== String(req.body.authorId)) {
    return res.status(403).json({ message: "본인 후기만 수정할 수 있습니다." });
  }
  review.text = String(req.body.text || "").trim();
  review.rating = Math.min(5, Math.max(1, Number(req.body.rating) || 3));
  review.tags = Array.isArray(req.body.tags) ? req.body.tags : [];
  review.sweet = Math.min(5, Math.max(1, Number(req.body.sweet) || 1));
  review.salty = Math.min(5, Math.max(1, Number(req.body.salty) || 1));
  review.spicy = Math.min(5, Math.max(1, Number(req.body.spicy) || 1));
  review.sour = Math.min(5, Math.max(1, Number(req.body.sour) || 1));
  review.caution = String(req.body.caution || "").trim();
  await post.save();
  return res.json({ post: serializePost(post) });
});

app.delete("/api/posts/:postId/reviews/:reviewId", async (req, res) => {
  const post = await Post.findById(req.params.postId);
  if (!post) return res.status(404).json({ message: "게시글을 찾을 수 없습니다." });
  const review = post.reviews.find((item) => item.id === req.params.reviewId);
  if (!review) return res.status(404).json({ message: "후기를 찾을 수 없습니다." });
  if (!req.query.authorId || review.authorId !== String(req.query.authorId)) {
    return res.status(403).json({ message: "본인 후기만 삭제할 수 있습니다." });
  }
  post.reviews = post.reviews.filter((item) => item.id !== req.params.reviewId);
  await post.save();
  return res.json({ post: serializePost(post) });
});

app.get("/api/products/misses", async (req, res) => {
  const limit = Math.min(Math.max(Number(req.query.limit || 50), 1), 200);
  const misses = await ProductLookupMiss.find({})
    .sort({ failureCount: -1, lastTriedAt: -1 })
    .limit(limit)
    .lean();

  return res.json({
    misses: misses.map((item) => ({
      barcode: item.barcode,
      failureCount: item.failureCount,
      checkedSources: item.checkedSources || [],
      lastErrorMessages: item.lastErrorMessages || [],
      firstSeenAt: item.firstSeenAt,
      lastTriedAt: item.lastTriedAt,
    })),
  });
});

app.get("/api/products/cu", async (req, res) => {
  const {
    query = "",
    label = "",
    limit = "100",
  } = req.query;
  const normalizedQuery = normalizeName(query);
  const pageLimit = Math.min(Math.max(Number(limit || 100), 1), 500);
  const filter = {};

  if (normalizedQuery) {
    filter.$or = [
      { normalizedName: { $regex: normalizedQuery.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), $options: "i" } },
      { barcode: String(query).replace(/[^0-9A-Za-z]/g, "") },
    ];
  }
  if (label === "new") filter.isNewFlag = true;
  if (label === "pb") filter.isPb = true;

  const products = await CuProduct.find(filter)
    .sort({ isNewFlag: -1, isPb: -1, lastSeenAt: -1, name: 1 })
    .limit(pageLimit)
    .lean();

  return res.json({ products: products.map(serializeCuProduct) });
});

app.get("/api/products/cu/labels", async (req, res) => {
  const query = String(req.query.query || "").trim();
  const barcode = normalizeBarcode(req.query.barcode || "");
  if (!query && !barcode) {
    return res.json({ labels: [], products: [] });
  }

  const normalizedQuery = normalizeName(query);
  const filters = [];
  if (barcode) filters.push({ barcode });
  if (normalizedQuery) {
    filters.push({
      normalizedName: {
        $regex: normalizedQuery.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"),
        $options: "i",
      },
    });
  }

  const products = await CuProduct.find({ $or: filters }).limit(10).lean();
  const hasNew = products.some((product) => product.isNewFlag || product.isNewByDiff);
  const hasPb = products.some((product) => product.isPb);
  return res.json({
    labels: [
      ...(hasNew ? ["new"] : []),
      ...(hasPb ? ["pb"] : []),
    ],
    products: products.map(serializeCuProduct),
  });
});

app.post("/api/products/cu/refresh", async (req, res) => {
  try {
    const result = await refreshCuProducts();
    return res.json(result);
  } catch (error) {
    return res.status(502).json({
      message: "CU 상품 수집에 실패했습니다.",
      error: String(error.message || error),
    });
  }
});

app.get("/api/products/convenience", async (req, res) => {
  const {
    query = "",
    store = "",
    label = "",
    limit = "100",
  } = req.query;
  const normalizedQuery = normalizeName(query);
  const pageLimit = Math.min(Math.max(Number(limit || 100), 1), 500);
  const filter = {};
  if (store) filter.store = String(store);
  if (normalizedQuery) {
    filter.$or = [
      { normalizedName: { $regex: normalizedQuery.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), $options: "i" } },
      { barcode: String(query).replace(/[^0-9A-Za-z]/g, "") },
    ];
  }
  if (label === "new") filter.isNewFlag = true;
  if (label === "pb") filter.isPb = true;

  const products = await ConvenienceProduct.find(filter)
    .sort({ isNewFlag: -1, isPb: -1, lastSeenAt: -1, name: 1 })
    .limit(pageLimit)
    .lean();
  return res.json({ products: products.map(serializeConvenienceProduct) });
});

app.get("/api/products/convenience/labels", async (req, res) => {
  const query = String(req.query.query || "").trim();
  const barcode = normalizeBarcode(req.query.barcode || "");
  if (!query && !barcode) {
    return res.json({ labels: [], products: [] });
  }

  const normalizedQuery = normalizeName(query);
  const filters = [];
  if (barcode) filters.push({ barcode });
  if (normalizedQuery) {
    filters.push({
      normalizedName: {
        $regex: normalizedQuery.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"),
        $options: "i",
      },
    });
  }

  const products = await ConvenienceProduct.find({ $or: filters }).limit(20).lean();
  const labels = [];
  for (const product of products) {
    if (product.isNewFlag || product.isNewByDiff) labels.push(`${product.store}:new`);
    if (product.isPb) labels.push(`${product.store}:pb`);
  }
  return res.json({
    labels: [...new Set(labels)],
    products: products.map(serializeConvenienceProduct),
  });
});

app.post("/api/products/convenience/refresh", async (req, res) => {
  try {
    const result = await refreshConvenienceProducts();
    return res.json(result);
  } catch (error) {
    return res.status(502).json({
      message: "편의점 상품 수집에 실패했습니다.",
      error: String(error.message || error),
    });
  }
});

app.get("/api/products/lookup/:barcode", async (req, res) => {
  const barcode = normalizeBarcode(req.params.barcode);
  if (!barcode) {
    return res.status(400).json({ message: "바코드가 비어 있습니다." });
  }

  const cuProduct = await CuProduct.findOne({ barcode }).lean();
  if (cuProduct) {
    return res.json({
      product: serializeProduct(
        {
          barcode,
          officialName: cuProduct.name,
          normalizedName: normalizeName(cuProduct.name),
          brand: null,
          manufacturer: null,
          seller: null,
          store: "CU",
          capacity: null,
          price: parseCuPriceToNumber(cuProduct.price),
          calories: null,
          aliases: [],
          categories: [
            ...(cuProduct.isNewFlag || cuProduct.isNewByDiff ? ["CU 신상품"] : []),
            ...(cuProduct.isPb ? ["CU PB"] : []),
          ],
          images: { product: cuProduct.imageUrl || null, meta: null },
          source: "cu-crawler",
          sources: [],
          verificationStatus: "auto-imported",
          lookupCount: 1,
          tentative: false,
          warning: null,
          lastVerifiedAt: cuProduct.lastCrawledAt || cuProduct.updatedAt || new Date(),
        },
        { cached: true }
      ),
    });
  }

  const convenienceProduct = await ConvenienceProduct.findOne({ barcode }).lean();
  if (convenienceProduct) {
    return res.json({
      product: serializeProduct(
        {
          barcode,
          officialName: convenienceProduct.name,
          normalizedName: normalizeName(convenienceProduct.name),
          brand: null,
          manufacturer: null,
          seller: null,
          store: convenienceProduct.store,
          capacity: null,
          price: parseCuPriceToNumber(convenienceProduct.price),
          calories: null,
          aliases: [],
          categories: [
            ...(convenienceProduct.isNewFlag || convenienceProduct.isNewByDiff ? [`${convenienceProduct.store} 신상품`] : []),
            ...(convenienceProduct.isPb ? [`${convenienceProduct.store} PB`] : []),
          ],
          images: { product: convenienceProduct.imageUrl || null, meta: null },
          source: "convenience-product-crawler",
          sources: [],
          verificationStatus: "auto-imported",
          lookupCount: 1,
          tentative: false,
          warning: null,
          lastVerifiedAt: convenienceProduct.lastCrawledAt || convenienceProduct.updatedAt || new Date(),
        },
        { cached: true }
      ),
    });
  }

  const cachedProduct = await Product.findOne({ barcode }).lean();
  if (cachedProduct) {
    return res.json({
      product: serializeProduct(cachedProduct, { cached: true }),
    });
  }

  let resolvedProduct = null;
  let providerErrors = [];
  try {
    const result = await fetchProductFromProviders(barcode);
    resolvedProduct = result.product;
    providerErrors = result.errors;
  } catch (error) {
    return res.status(502).json({ message: "HACCP 상품 조회에 실패했습니다.", error: String(error.message || error) });
  }

  if (!resolvedProduct) {
    try {
      await recordProductLookupMiss(
        barcode,
        PRODUCT_LOOKUP_SOURCES,
        providerErrors
      );
    } catch (_) {}

    return res.status(404).json({
      message: "연결된 상품 DB들에서 상품명을 찾지 못했습니다.",
      checkedSources: PRODUCT_LOOKUP_SOURCES,
      providerErrors,
    });
  }

  try {
    resolvedProduct = await upsertProductCandidate(barcode, resolvedProduct);
    return res.json({
      product: serializeProduct(resolvedProduct, { cached: false }),
    });
  } catch (error) {
    return res.status(500).json({ message: "상품 응답 생성에 실패했습니다.", error: String(error.message || error) });
  }
});

const webBuildPath = path.join(__dirname, "..", "frontend", "pyeonpick_app", "build", "web");
app.use(
  express.static(webBuildPath, {
    setHeaders: (res, filePath) => {
      res.setHeader("Cache-Control", "no-store, no-cache, must-revalidate");
      if (
        filePath.endsWith("index.html") ||
        filePath.endsWith("flutter_bootstrap.js") ||
        filePath.endsWith("flutter_service_worker.js")
      ) {
        res.setHeader("Clear-Site-Data", '"cache"');
      }
    },
  })
);

app.get(/^(?!\/api).*/, (req, res) => {
  res.setHeader("Cache-Control", "no-store, no-cache, must-revalidate");
  res.setHeader("Clear-Site-Data", '"cache"');
  res.sendFile(path.join(webBuildPath, "index.html"));
});

async function start() {
  if (process.env.NODE_ENV === "production" && usesDefaultJwtSecret) {
    throw new Error("JWT_SECRET is required when NODE_ENV=production.");
  }

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

  await resetDemoDataIfRequested();
  await seedIfNeeded();
  await backfillLegacyPosts();
  await backfillLegacyProducts();
  await Product.deleteMany({ source: "local-fallback-catalog" });
  await refreshTopFiveBadges();
  scheduleCuProductRefresh();

  app.listen(PORT, "0.0.0.0", () => {
    console.log(`PyeonPick full-stack server running at http://0.0.0.0:${PORT} using ${mongoLabel}`);
  });
}

if (require.main === module) {
  start().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}

module.exports = {
  refreshConvenienceProducts,
  refreshCuProducts,
};
