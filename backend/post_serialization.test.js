const test = require("node:test");
const assert = require("node:assert/strict");

const {
  nextReactionState,
  setReactionState,
  serializeBattleMatch,
  serializePostCatalog,
} = require("./server");

test("post catalog replaces stored base64 images with lightweight image URLs", () => {
  const post = {
    _id: { toString: () => "post-123" },
    authorId: "author-1",
    authorNickname: "테스터",
    title: "테스트 조합",
    content: "내용",
    categories: [],
    comments: [],
    reviews: [],
    imageData: undefined,
    imageDatas: undefined,
    imageUrl: null,
    imageUrls: [],
    _storedImageCount: 2,
  };
  const req = {
    protocol: "https",
    get(name) {
      if (name === "x-forwarded-proto") return "https";
      if (name === "host") return "pyeonpick.example";
      return "";
    },
  };

  const result = serializePostCatalog(post, null, req);

  assert.equal(result.imageData, null);
  assert.deepEqual(result.imageDatas, []);
  assert.deepEqual(result.imageUrls, [
    "https://pyeonpick.example/api/posts/post-123/images/0",
    "https://pyeonpick.example/api/posts/post-123/images/1",
  ]);
  assert.equal(JSON.stringify(result).includes("base64"), false);
});

test("battle serialization replaces inline images with lightweight image URLs", () => {
  const match = {
    _id: { toString: () => "507f1f77bcf86cd799439011" },
    id: "battle-1",
    title: "테스트 픽쇼츠",
    authorId: "author-1",
    authorNickname: "테스터",
    leftVoterIds: [],
    rightVoterIds: [],
    leftCustomImageUrl: "data:image/png;base64,AAAA",
    rightCustomImageUrl: "https://example.com/right.jpg",
  };
  const req = {
    protocol: "https",
    get(name) {
      if (name === "x-forwarded-proto") return "https";
      if (name === "host") return "pyeonpick.example";
      return "";
    },
  };

  const result = serializeBattleMatch(match, "", req);

  assert.equal(
    result.leftCustomImageUrl,
    "https://pyeonpick.example/api/battles/507f1f77bcf86cd799439011/images/left",
  );
  assert.equal(result.rightCustomImageUrl, "https://example.com/right.jpg");
  assert.equal(JSON.stringify(result).includes("base64"), false);
});

test("reaction state switches like and dislike without touching unrelated user data", () => {
  const post = {
    _id: { toString: () => "post-1" },
    likes: 4,
    dislikes: 2,
    likeEvents: [{ userId: "user-1", createdAt: new Date() }],
  };
  const user = {
    likedPostIds: ["post-1", "post-2"],
    dislikedPostIds: ["post-3"],
  };

  const disliked = nextReactionState(post, user, "user-1", "dislike");

  assert.equal(disliked.likes, 3);
  assert.equal(disliked.dislikes, 3);
  assert.equal(disliked.likedByMe, false);
  assert.equal(disliked.dislikedByMe, true);
  assert.deepEqual(disliked.likedPostIds, ["post-2"]);
  assert.deepEqual(disliked.dislikedPostIds.sort(), ["post-1", "post-3"]);
  assert.equal(disliked.likeEvents.length, 0);
});

test("desired reaction state is idempotent for safe request retries", () => {
  const existingEvent = { userId: "user-1", createdAt: new Date("2026-01-01") };
  const post = {
    _id: { toString: () => "post-1" },
    likes: 4,
    dislikes: 2,
    likeEvents: [existingEvent],
  };
  const user = {
    likedPostIds: ["post-1", "post-2"],
    dislikedPostIds: ["post-3"],
  };

  const liked = setReactionState(post, user, "user-1", "like");

  assert.equal(liked.likes, 4);
  assert.equal(liked.dislikes, 2);
  assert.equal(liked.likedByMe, true);
  assert.equal(liked.dislikedByMe, false);
  assert.deepEqual(liked.likedPostIds, ["post-1", "post-2"]);
  assert.deepEqual(liked.dislikedPostIds, ["post-3"]);
  assert.equal(liked.likeEvents.length, 1);
  assert.equal(liked.likeEvents[0], existingEvent);
});
