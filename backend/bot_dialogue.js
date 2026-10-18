const legacySituationTags = new Set([
  '등교길 추천', '야식 추천', '간식 추천', '점심 대용', '아침 대용',
  '공부할 때 추천', '드라이브 간식', '영화 보며 먹기 좋아요',
  '여행 갈 때 챙기기 좋아요', '피크닉 추천', '운동 후 추천',
  '다이어트 할 때 추천',
]);

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
    categories: (post.categories || [])
      .map(String)
      .filter((category) => !legacySituationTags.has(category))
      .slice(0, 12),
    usedProducts: (post.details?.usedProducts || []).slice(0, 8),
  }));
}

function dialogueInput({ prompt, history, candidates, setup, draft, pendingClarification, maximumBudget, minimumPrice }) {
  return [
    {
      role: 'developer',
      content: '너는 사용자의 편의점 장보기에 같이 온 친근한 편봇이야. 자연스럽고 다정한 한국어 반말로 짧게 대화해. 아무거나 추천, 야식 추천, 비교, 잡담처럼 자유로운 질문을 받고 기분 분석을 강요하거나 매번 되묻지 마. 기분·맛·카테고리는 여러 추천 도구 중 하나일 뿐이야. ~입니다 같은 보고서 말투와 반복 설문을 피하고 최근 대화의 비교·수정에도 직접 답해. 보통 2~4문장, 꼭 필요한 질문은 한 번에 하나만 해. 추천을 제시할 때는 반드시 candidates에 포함된 조합 공유 게시글을 하나 이상 근거로 사용해. candidates가 비어 있으면 상품이나 조합을 임의로 추천하지 말고 예산이나 조건을 짧게 다시 물어봐. 추천 상품명과 가격은 candidates에 있는 것만 사용하고 없는 상품이나 재고를 지어내지 마. 사용자의 현재 명시적 요청이 초기 설정보다 우선이야.',
    },
    ...safeHistory(history),
    {
      role: 'user',
      content: JSON.stringify({
        currentRequest: String(prompt).slice(0, 2000),
        candidates, setup,
        constraints: { maximumBudget, minimumPrice, pendingClarification },
        fallbackDraft: String(draft || '').slice(0, 2000),
      }),
    },
  ];
}

module.exports = { safeHistory, eligibleCandidates, dialogueInput };
