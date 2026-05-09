const categories = ["달달", "매콤", "신", "짭잘", "건강"];

const seededPosts = [
  {
    id: crypto.randomUUID(),
    title: "딸기우유 프레첼 한입 조합",
    content:
      "차갑게 둔 딸기우유를 한 모금 마시고 프레첼을 바로 먹으면 단짠이 깔끔하게 이어져요. 야근 끝나고 당 떨어질 때 가장 만족도가 높았어요.",
    priceMin: 2900,
    priceMax: 3600,
    categories: ["달달", "짭잘"],
    likes: 31,
    comments: ["이거 시험기간에 진짜 좋아요.", "프레첼 대신 치즈크래커 넣어도 맛있어요."],
    createdAt: "2026-05-09T09:10:00+09:00",
    image:
      "https://images.unsplash.com/photo-1542826438-bd32f43d626f?auto=format&fit=crop&w=1200&q=80",
    likedByMe: false,
    expanded: false,
    commentsOpen: false,
    everTopFiveAt: null,
  },
  {
    id: crypto.randomUUID(),
    title: "불닭삼각김밥 + 쿨피스 리셋 조합",
    content:
      "매운맛이 확 올라온 다음 쿨피스로 바로 식히면 중독성이 커져요. 스트레스 풀고 싶을 때 추천하는 가장 기본적인 편의점 꿀조합이에요.",
    priceMin: 2500,
    priceMax: 3300,
    categories: ["매콤"],
    likes: 54,
    comments: ["맵찔이도 쿨피스 있으면 가능해요.", "전자레인지 20초 더 돌리면 더 맛있어요."],
    createdAt: "2026-05-09T08:42:00+09:00",
    image:
      "https://images.unsplash.com/photo-1515003197210-e0cd71810b5f?auto=format&fit=crop&w=1200&q=80",
    likedByMe: false,
    expanded: false,
    commentsOpen: false,
    everTopFiveAt: null,
  },
  {
    id: crypto.randomUUID(),
    title: "요거트 + 컵과일 상큼 디저트",
    content:
      "달지 않은 그릭요거트에 컵과일을 올려 먹으면 포만감도 있고 후식 느낌도 좋아요. 아침 대용으로도 깔끔해서 자주 사 먹게 돼요.",
    priceMin: 4300,
    priceMax: 5200,
    categories: ["신", "건강"],
    likes: 47,
    comments: ["출근길 조합으로 저장했어요."],
    createdAt: "2026-05-08T20:18:00+09:00",
    image:
      "https://images.unsplash.com/photo-1488477181946-6428a0291777?auto=format&fit=crop&w=1200&q=80",
    likedByMe: false,
    expanded: false,
    commentsOpen: false,
    everTopFiveAt: null,
  },
  {
    id: crypto.randomUUID(),
    title: "참치마요 김밥 + 청양마요 소스",
    content:
      "느끼할 수 있는 참치마요에 청양마요를 더하면 확실하게 감칠맛이 살아나요. 매콤한데 과하지 않아서 입문 조합으로 좋아요.",
    priceMin: 3200,
    priceMax: 4100,
    categories: ["매콤", "짭잘"],
    likes: 29,
    comments: ["소스 반만 넣어도 충분했어요."],
    createdAt: "2026-05-08T18:55:00+09:00",
    image:
      "https://images.unsplash.com/photo-1553621042-f6e147245754?auto=format&fit=crop&w=1200&q=80",
    likedByMe: false,
    expanded: false,
    commentsOpen: false,
    everTopFiveAt: null,
  },
  {
    id: crypto.randomUUID(),
    title: "얼음컵 아메리카노 + 초코바삭롤",
    content:
      "씁쓸한 커피에 바삭한 초코롤이 붙으면 카페 대신 편의점으로 바로 향하게 돼요. 점심 뒤 졸릴 때 제일 무난하고 만족감 높은 조합입니다.",
    priceMin: 3800,
    priceMax: 4700,
    categories: ["달달"],
    likes: 63,
    comments: ["이건 거의 국룰 조합이네요."],
    createdAt: "2026-05-08T13:02:00+09:00",
    image:
      "https://images.unsplash.com/photo-1509042239860-f550ce710b93?auto=format&fit=crop&w=1200&q=80",
    likedByMe: false,
    expanded: false,
    commentsOpen: false,
    everTopFiveAt: null,
  },
  {
    id: crypto.randomUUID(),
    title: "닭가슴살볼 + 구운계란 든든 조합",
    content:
      "간단히 단백질 챙기고 싶은 날에 제일 실속 있어요. 소스가 강하지 않아서 질리지 않고, 운동 전후 간식으로도 부담이 적어요.",
    priceMin: 4200,
    priceMax: 5600,
    categories: ["건강", "짭잘"],
    likes: 22,
    comments: ["운동 끝나고 자주 먹는 조합이에요."],
    createdAt: "2026-05-08T09:20:00+09:00",
    image:
      "https://images.unsplash.com/photo-1512621776951-a57141f2eefd?auto=format&fit=crop&w=1200&q=80",
    likedByMe: false,
    expanded: false,
    commentsOpen: false,
    everTopFiveAt: null,
  },
  {
    id: crypto.randomUUID(),
    title: "레몬탄산수 + 새우칩 상큼짭짤",
    content:
      "느끼하지 않게 계속 손이 가는 조합이에요. 탄산이 입안을 정리해줘서 영화 볼 때 오래 먹기 좋고, 생각보다 질리지 않아요.",
    priceMin: 2600,
    priceMax: 3400,
    categories: ["신", "짭잘"],
    likes: 41,
    comments: ["맥주 느낌 대신 가볍게 즐기기 좋네요."],
    createdAt: "2026-05-07T22:11:00+09:00",
    image:
      "https://images.unsplash.com/photo-1513558161293-cdaf765ed2fd?auto=format&fit=crop&w=1200&q=80",
    likedByMe: false,
    expanded: false,
    commentsOpen: false,
    everTopFiveAt: null,
  },
  {
    id: crypto.randomUUID(),
    title: "쫀득빵 + 바닐라우유 야식 조합",
    content:
      "폭신한 빵에 차가운 우유를 곁들이면 늦은 밤에 기분 좋게 마무리되는 조합이에요. 너무 자극적이지 않아서 야식으로 무난해요.",
    priceMin: 3000,
    priceMax: 3900,
    categories: ["달달"],
    likes: 35,
    comments: ["전자레인지 10초 돌리면 더 좋아요."],
    createdAt: "2026-05-07T19:08:00+09:00",
    image:
      "https://images.unsplash.com/photo-1509440159596-0249088772ff?auto=format&fit=crop&w=1200&q=80",
    likedByMe: false,
    expanded: false,
    commentsOpen: false,
    everTopFiveAt: null,
  },
];

const state = {
  posts: seededPosts,
  selectedFeature: "communication",
  selectedCategories: new Set(),
  sort: "latest",
  imagePreview: null,
};

const featureViews = {
  communication: document.getElementById("communicationView"),
  bot: document.getElementById("botView"),
  health: document.getElementById("healthView"),
  scanner: document.getElementById("scannerView"),
  profile: document.getElementById("profileView"),
};

const postsFeed = document.getElementById("postsFeed");
const postTemplate = document.getElementById("postTemplate");
const featureButtons = [...document.querySelectorAll(".feature-chip")];
const sortButtons = [...document.querySelectorAll(".sort-button")];
const searchInput = document.getElementById("searchInput");
const minPriceFilter = document.getElementById("minPriceFilter");
const maxPriceFilter = document.getElementById("maxPriceFilter");
const openComposer = document.getElementById("openComposer");
const composerModal = document.getElementById("composerModal");
const closeComposer = document.getElementById("closeComposer");
const composerForm = document.getElementById("composerForm");
const imageInput = document.getElementById("imageInput");
const imagePreview = document.getElementById("imagePreview");
const titleInput = document.getElementById("titleInput");
const contentInput = document.getElementById("contentInput");
const priceMinInput = document.getElementById("priceMinInput");
const priceMaxInput = document.getElementById("priceMaxInput");
const customCategoryInput = document.getElementById("customCategoryInput");
const categoryOptions = document.getElementById("categoryOptions");
const formError = document.getElementById("formError");

function formatDateTime(value) {
  const date = new Date(value);
  return new Intl.DateTimeFormat("ko-KR", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(date);
}

function formatDate(value) {
  const date = new Date(value);
  return new Intl.DateTimeFormat("ko-KR", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

function formatPriceRange(post) {
  return `${post.priceMin.toLocaleString()}~${post.priceMax.toLocaleString()}원`;
}

function applyTopFiveBadges() {
  const ranked = [...state.posts]
    .sort((a, b) => b.likes - a.likes || new Date(b.createdAt) - new Date(a.createdAt))
    .slice(0, 5);

  const topIds = new Set(ranked.map((post) => post.id));
  const now = new Date().toISOString();

  state.posts.forEach((post) => {
    if (topIds.has(post.id) && !post.everTopFiveAt) {
      post.everTopFiveAt = now;
    }
  });
}

function buildCategoryOptions() {
  categoryOptions.innerHTML = "";

  categories.forEach((category) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "category-pill";
    button.textContent = `#${category}`;

    button.addEventListener("click", () => {
      if (state.selectedCategories.has(category)) {
        state.selectedCategories.delete(category);
        button.classList.remove("active");
      } else {
        state.selectedCategories.add(category);
        button.classList.add("active");
      }
    });

    categoryOptions.appendChild(button);
  });
}

function getCustomCategories() {
  return customCategoryInput.value
    .split(/[\s,]+/)
    .map((item) => item.trim())
    .filter(Boolean)
    .map((item) => (item.startsWith("#") ? item.slice(1) : item))
    .filter(Boolean);
}

function getFilteredPosts() {
  const query = searchInput.value.trim().toLowerCase();
  const min = Number(minPriceFilter.value || 0);
  const max = Number(maxPriceFilter.value || 0);

  let filtered = [...state.posts].filter((post) => {
    const matchesQuery =
      !query ||
      (query.startsWith("#")
        ? post.categories.some((category) => category.toLowerCase().includes(query.slice(1)))
        : post.title.toLowerCase().includes(query));

    const matchesMin = !min || post.priceMax >= min;
    const matchesMax = !max || post.priceMin <= max;
    return matchesQuery && matchesMin && matchesMax;
  });

  filtered.sort((a, b) => {
    if (state.sort === "popular") {
      return b.likes - a.likes || new Date(b.createdAt) - new Date(a.createdAt);
    }
    return new Date(b.createdAt) - new Date(a.createdAt);
  });

  return filtered;
}

function renderPosts() {
  applyTopFiveBadges();
  postsFeed.innerHTML = "";
  const posts = getFilteredPosts();

  if (!posts.length) {
    const empty = document.createElement("div");
    empty.className = "placeholder-panel";
    empty.innerHTML = "<h2>검색 결과가 없어요.</h2><p>제목, #카테고리, 가격대를 조금 다르게 입력해 보세요.</p>";
    postsFeed.appendChild(empty);
    return;
  }

  posts.forEach((post) => {
    const fragment = postTemplate.content.cloneNode(true);
    const card = fragment.querySelector(".post-card");
    const date = fragment.querySelector(".post-date");
    const mainButton = fragment.querySelector(".post-main");
    const image = fragment.querySelector(".post-image");
    const bookmark = fragment.querySelector(".bookmark");
    const bookmarkDate = fragment.querySelector(".bookmark small");
    const title = fragment.querySelector(".post-title");
    const price = fragment.querySelector(".post-price");
    const tags = fragment.querySelector(".post-tags");
    const detail = fragment.querySelector(".post-detail");
    const content = fragment.querySelector(".post-content");
    const likeButton = fragment.querySelector(".like-button");
    const commentToggle = fragment.querySelector(".comment-toggle");
    const commentArea = fragment.querySelector(".comment-area");
    const commentList = fragment.querySelector(".comment-list");
    const commentForm = fragment.querySelector(".comment-form");
    const commentInput = fragment.querySelector(".comment-input");

    date.textContent = formatDateTime(post.createdAt);
    title.textContent = post.title || "제목 없는 꿀조합";
    price.textContent = formatPriceRange(post);
    content.textContent = post.content || "사진 중심 게시글입니다.";

    if (post.image) {
      image.style.backgroundImage = `url('${post.image}')`;
    } else {
      image.classList.add("placeholder");
    }

    post.categories.forEach((category) => {
      const tag = document.createElement("span");
      tag.className = "tag";
      tag.textContent = `#${category}`;
      tags.appendChild(tag);
    });

    if (post.everTopFiveAt) {
      bookmark.classList.remove("hidden");
      bookmarkDate.textContent = formatDate(post.everTopFiveAt);
    }

    likeButton.textContent = `♡ 하트 ${post.likes}`;
    if (post.likedByMe) {
      likeButton.classList.add("active");
      likeButton.textContent = `♥ 하트 ${post.likes}`;
    }

    commentToggle.textContent = `댓글 ${post.comments.length}`;

    if (post.expanded) {
      detail.classList.remove("hidden");
    }

    if (post.commentsOpen) {
      commentArea.classList.remove("hidden");
    }

    post.comments.forEach((comment) => {
      const item = document.createElement("div");
      item.className = "comment-item";
      item.textContent = comment;
      commentList.appendChild(item);
    });

    mainButton.addEventListener("click", () => {
      post.expanded = !post.expanded;
      renderPosts();
    });

    likeButton.addEventListener("click", (event) => {
      event.stopPropagation();
      post.likedByMe = !post.likedByMe;
      post.likes += post.likedByMe ? 1 : -1;
      renderPosts();
    });

    commentToggle.addEventListener("click", (event) => {
      event.stopPropagation();
      post.expanded = true;
      post.commentsOpen = !post.commentsOpen;
      renderPosts();
    });

    commentForm.addEventListener("submit", (event) => {
      event.preventDefault();
      const value = commentInput.value.trim();
      if (!value) {
        return;
      }
      post.comments.push(value);
      post.commentsOpen = true;
      post.expanded = true;
      renderPosts();
    });

    card.dataset.postId = post.id;
    postsFeed.appendChild(fragment);
  });
}

function switchFeature(feature) {
  state.selectedFeature = feature;
  featureButtons.forEach((button) => {
    button.classList.toggle("active", button.dataset.feature === feature);
  });

  Object.entries(featureViews).forEach(([key, view]) => {
    view.classList.toggle("active", key === feature);
  });
}

function resetComposer() {
  composerForm.reset();
  state.selectedCategories.clear();
  formError.textContent = "";
  state.imagePreview = null;
  imagePreview.className = "image-preview empty";
  imagePreview.innerHTML = "<span>사진을 올리면 여기에 미리보기가 보여요.</span>";
  [...document.querySelectorAll(".category-pill")].forEach((pill) => pill.classList.remove("active"));
}

function openComposerModal() {
  composerModal.classList.remove("hidden");
  composerModal.setAttribute("aria-hidden", "false");
}

function closeComposerModal() {
  composerModal.classList.add("hidden");
  composerModal.setAttribute("aria-hidden", "true");
  resetComposer();
}

featureButtons.forEach((button) => {
  button.addEventListener("click", () => switchFeature(button.dataset.feature));
});

sortButtons.forEach((button) => {
  button.addEventListener("click", () => {
    state.sort = button.dataset.sort;
    sortButtons.forEach((item) => item.classList.toggle("active", item === button));
    renderPosts();
  });
});

[searchInput, minPriceFilter, maxPriceFilter].forEach((input) => {
  input.addEventListener("input", renderPosts);
});

openComposer.addEventListener("click", () => {
  switchFeature("communication");
  openComposerModal();
});

closeComposer.addEventListener("click", closeComposerModal);
composerModal.querySelector(".modal-backdrop").addEventListener("click", closeComposerModal);

imageInput.addEventListener("change", (event) => {
  const [file] = event.target.files;
  if (!file) {
    state.imagePreview = null;
    return;
  }

  const reader = new FileReader();
  reader.onload = () => {
    state.imagePreview = reader.result;
    imagePreview.className = "image-preview";
    imagePreview.innerHTML = `<img src="${reader.result}" alt="업로드 미리보기" />`;
  };
  reader.readAsDataURL(file);
});

composerForm.addEventListener("submit", (event) => {
  event.preventDefault();

  const title = titleInput.value.trim();
  const content = contentInput.value.trim();
  const priceMin = Number(priceMinInput.value);
  const priceMax = Number(priceMaxInput.value);
  const customCategories = getCustomCategories();
  const allCategories = [...new Set([...state.selectedCategories, ...customCategories])];

  const hasImage = Boolean(state.imagePreview);
  const hasTextSet = Boolean(title && content);
  const hasValidPrice = Number.isFinite(priceMin) && Number.isFinite(priceMax) && priceMin > 0 && priceMax >= priceMin;

  if (!hasImage && !hasTextSet) {
    formError.textContent = "사진 또는 제목+자세한 내용을 입력해야 게시할 수 있어요.";
    return;
  }

  if (!hasValidPrice) {
    formError.textContent = "가격 범위를 올바르게 입력해 주세요.";
    return;
  }

  if (!allCategories.length) {
    formError.textContent = "카테고리를 하나 이상 선택하거나 직접 만들어 주세요.";
    return;
  }

  formError.textContent = "";

  state.posts.unshift({
    id: crypto.randomUUID(),
    title: title || "제목 없는 꿀조합",
    content,
    priceMin,
    priceMax,
    categories: allCategories,
    likes: 0,
    comments: [],
    createdAt: new Date().toISOString(),
    image: state.imagePreview,
    likedByMe: false,
    expanded: false,
    commentsOpen: false,
    everTopFiveAt: null,
  });

  state.sort = "latest";
  sortButtons.forEach((button) => button.classList.toggle("active", button.dataset.sort === "latest"));
  renderPosts();
  closeComposerModal();
});

buildCategoryOptions();
applyTopFiveBadges();
renderPosts();
