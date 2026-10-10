const test = require("node:test");
const assert = require("node:assert/strict");

const { serializePostCatalog } = require("./server");

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
