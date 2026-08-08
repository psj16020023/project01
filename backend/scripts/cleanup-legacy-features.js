require("dotenv").config({ path: require("path").join(__dirname, "..", ".env") });

const mongoose = require("mongoose");

async function dropCollectionIfExists(db, collectionName) {
  const collections = await db
    .listCollections({ name: collectionName }, { nameOnly: true })
    .toArray();
  if (collections.length === 0) {
    return { dropped: false };
  }
  await db.collection(collectionName).drop();
  return { dropped: true };
}

async function main() {
  const mongoUri = String(process.env.MONGO_URI || "").trim();
  if (!mongoUri) {
    throw new Error("MONGO_URI is required. Add it to backend/.env before running this migration.");
  }

  await mongoose.connect(mongoUri);
  const db = mongoose.connection.db;

  const userCleanup = await db.collection("users").updateMany(
    {},
    {
      $unset: {
        researchPosts: "",
        savedResearchPostIds: "",
        savedCombinations: "",
      },
    }
  );
  const storeReviews = await dropCollectionIfExists(db, "storereviews");

  console.log(
    JSON.stringify(
      {
        usersMatched: userCleanup.matchedCount,
        usersModified: userCleanup.modifiedCount,
        droppedStoreReviews: storeReviews.dropped,
        preservedCollections: [
          "products",
          "productlookupmisses",
          "cuproducts",
          "posts",
          "users",
        ],
      },
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
