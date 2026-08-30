const tastePatterns = {
  '달달': /초코|딸기우유|달달|쿠키|케이크|아이스크림/,
  '매콤': /불닭|마라|매콤|청양|떡볶이/,
  '새콤': /새콤|레몬|라임|식초/,
  '짭짤': /짭짤|소금|간장/,
};

// A vote is a weak preference signal, not a dislike of the other option.
function topicTokens(value) {
  return new Set(String(value || '').toLowerCase().match(/[가-힣a-z0-9]{2,}/g) || []);
}

function sameTopic(matchTitle, prompt) {
  const promptTokens = topicTokens(prompt);
  return promptTokens.size > 0 && [...topicTokens(matchTitle)].some((matchToken) =>
    [...promptTokens].some((promptToken) =>
      matchToken.includes(promptToken) || promptToken.includes(matchToken)
    )
  );
}

function choiceCategories(match, side, byId) {
  const post = byId.get(String(match[`${side}PostId`]));
  const title = String(match[`${side}CustomTitle`] || post?.title || '').slice(0, 160);
  const categories = new Set((post?.categories || []).map(String));
  for (const [taste, pattern] of Object.entries(tastePatterns)) {
    if (pattern.test(title)) categories.add(taste);
  }
  return { title, categories };
}

function buildVotePreferences(matches, posts, userId, prompt = '') {
  const byId = new Map(posts.map((post) => [String(post._id || post.id), post]));
  const seen = new Set();
  const counts = new Map();
  const recentChoices = [];
  let sampleCount = 0;
  for (const match of matches) {
    const id = String(match._id || match.id);
    if (seen.has(id)) continue;
    seen.add(id);
    const left = (match.leftVoterIds || []).map(String).includes(String(userId));
    const right = (match.rightVoterIds || []).map(String).includes(String(userId));
    if (left === right) continue;
    const side = left ? 'left' : 'right';
    const chosen = choiceCategories(match, side, byId);
    const rejected = choiceCategories(match, left ? 'right' : 'left', byId);
    const topicMatch = sameTopic(match.title, prompt);
    for (const category of chosen.categories) {
      counts.set(category, (counts.get(category) || 0) + (topicMatch ? 2 : 1));
    }
    if (topicMatch) {
      for (const category of rejected.categories) {
        counts.set(category, (counts.get(category) || 0) - 1);
      }
    }
    sampleCount++;
    if (chosen.title && recentChoices.length < 6) recentChoices.push(chosen.title);
  }
  return {
    sampleCount,
    categoryWeights: Object.fromEntries([...counts].map(([key, count]) => [key, count / sampleCount])),
    recentChoices,
  };
}

function safeHistory(messages) {
  return (Array.isArray(messages) ? messages : [])
    .filter((m) => m && ['user', 'assistant'].includes(m.role) && typeof m.text === 'string')
    .slice(-10)
    .map((m) => ({ role: m.role, content: m.text.slice(0, 1500) }));
}

function eligibleCandidates(posts, maximumBudget, minimumPrice) {
  const maximum = Number.isFinite(maximumBudget) ? maximumBudget : null;
  const minimum = Number.isFinite(minimumPrice) ? minimumPrice : null;
  if (maximum === null && minimum === null) return [];
  return posts.filter((post) =>
    Number.isFinite(post.priceMin) && Number.isFinite(post.priceMax) &&
    post.priceMin > 0 && post.priceMax >= post.priceMin &&
    (maximum === null || post.priceMax <= maximum) &&
    (minimum === null || post.priceMin >= minimum)
  ).slice(0, 3).map((post) => ({
    title: String(post.title).slice(0, 160),
    priceMin: post.priceMin,
    priceMax: post.priceMax,
    categories: (post.categories || []).slice(0, 12),
    usedProducts: (post.details?.usedProducts || []).slice(0, 8),
  }));
}

function dialogueInput({ prompt, history, candidates, preferences, setup, draft, pendingClarification, maximumBudget, minimumPrice }) {
  return [
    {
      role: 'developer',
      content: '너는 사용자의 편의점 장보기에 같이 온 친근한 편봇이야. 자연스럽고 다정한 한국어 반말로 짧게 대화해. 아무거나 추천, 야식 추천, 비교, 잡담처럼 자유로운 질문을 받고 기분 분석을 강요하거나 매번 되묻지 마. 기분·맛·카테고리는 여러 추천 도구 중 하나일 뿐이야. ~입니다 같은 보고서 말투와 반복 설문을 피하고 최근 대화의 비교·수정에도 직접 답해. 보통 2~4문장, 꼭 필요한 질문은 한 번에 하나만 해. 추천을 제시할 때는 반드시 candidates에 포함된 조합 공유 게시글을 하나 이상 근거로 사용해. candidates가 비어 있으면 상품이나 조합을 임의로 추천하지 말고 예산이나 조건을 짧게 다시 물어봐. 추천 상품명과 가격은 candidates에 있는 것만 사용하고 없는 상품이나 재고를 지어내지 마. 사용자의 현재 명시적 요청이 setup과 투표 추정보다 우선이야. 같은 주제의 투표 선택은 미선택보다 먼저 고려하되 미선택을 싫어요로 단정하지 마.',
    },
    ...safeHistory(history),
    {
      role: 'user',
      content: JSON.stringify({
        currentRequest: String(prompt).slice(0, 2000),
        candidates, preferences, setup,
        constraints: { maximumBudget, minimumPrice, pendingClarification },
        fallbackDraft: String(draft || '').slice(0, 2000),
      }),
    },
  ];
}

module.exports = { buildVotePreferences, safeHistory, eligibleCandidates, dialogueInput };
