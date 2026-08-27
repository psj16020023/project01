# PyeonPick Workflow

- For requested app changes, fix observed errors, run relevant automated tests,
  Flutter analysis, and a production web build before publishing.
- The user wants completed changes applied to the existing Render deployment
  and the live site opened after verification, unless they request local-only
  work. Commit only task-related files and do not include local credentials or
  generated preview artifacts.
- Verify the deployed revision and relevant live behavior before reporting that
  a change is deployed. Clearly distinguish local verification from live checks.
- Never run test servers against the production MongoDB. Explicitly override
  MONGO_URI and OPENAI_API_KEY with empty values for isolated tests so dotenv
  cannot load the production values from backend/.env.
- Preserve real product photos. Keep labels and voting controls outside photos.
