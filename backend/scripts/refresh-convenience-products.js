require("dotenv").config({ path: require("path").join(__dirname, "..", ".env") });

const mongoose = require("mongoose");
const { refreshConvenienceProducts } = require("../server");

async function main() {
  const mongoUri = String(process.env.MONGO_URI || "").trim();
  if (!mongoUri) {
    throw new Error("MONGO_URI is required. Add it to backend/.env before running this crawler.");
  }
  await mongoose.connect(mongoUri);
  const result = await refreshConvenienceProducts();
  console.log(JSON.stringify(result, null, 2));
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await mongoose.disconnect().catch(() => {});
  });
