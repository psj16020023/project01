process.env.MONGO_URI = "";
process.env.OPENAI_API_KEY = "";

const test = require("node:test");
const assert = require("node:assert/strict");
const mongoose = require("mongoose");
const { MongoMemoryServer } = require("mongodb-memory-server");

const {
  legacyCuProductToConvenienceProduct,
  migrateLegacyCuProducts,
} = require("./server");

test("legacy CU products are copied into the shared collection before the old collection is removed", async (t) => {
  const mongoServer = await MongoMemoryServer.create();
  await mongoose.connect(mongoServer.getUri());
  t.after(async () => {
    await mongoose.disconnect();
    await mongoServer.stop();
  });

  const firstSeenAt = new Date("2026-01-02T03:04:05.000Z");
  await mongoose.connection.db.collection("cuproducts").insertOne({
    id: "cu-123",
    productId: "123",
    name: "  TEST 상품  ",
    price: "2,000",
    imageUrl: "https://example.com/cu-123.jpg",
    barcode: "8801234567890",
    isNewFlag: true,
    isPb: true,
    categoryCode: "10",
    firstSeenAt,
    lastSeenAt: firstSeenAt,
    lastCrawledAt: firstSeenAt,
  });

  const result = await migrateLegacyCuProducts();

  assert.deepEqual(result, { migrated: 1, removedLegacyCollection: true });
  const migrated = await mongoose.connection.db
    .collection("convenienceproducts")
    .findOne({ id: "cu-123" });
  assert.equal(migrated.store, "CU");
  assert.equal(migrated.productId, "123");
  assert.equal(migrated.normalizedName, "test 상품");
  assert.deepEqual(migrated.tags, ["신상품", "PB"]);
  assert.equal(migrated.categoryCode, "10");
  assert.equal(
    await mongoose.connection.db
      .listCollections({ name: "cuproducts" }, { nameOnly: true })
      .hasNext(),
    false
  );
});

test("legacy CU conversion rejects incomplete product documents", () => {
  assert.equal(legacyCuProductToConvenienceProduct({ productId: "", name: "상품" }), null);
  assert.equal(legacyCuProductToConvenienceProduct({ productId: "123", name: "" }), null);
});
