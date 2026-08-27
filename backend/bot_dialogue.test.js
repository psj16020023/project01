const test = require('node:test');
const assert = require('node:assert/strict');
const { buildVotePreferences, safeHistory, eligibleCandidates, dialogueInput } = require('./bot_dialogue');

test('only the authenticated user choices contribute; duplicate matches count once', () => {
  const matches = [
    { _id: 'a', leftPostId: 'sweet', rightPostId: 'spicy', leftVoterIds: ['me'], rightVoterIds: ['other'] },
    { _id: 'a', leftPostId: 'sweet', leftVoterIds: ['me'] },
    { _id: 'b', rightPostId: 'spicy', rightVoterIds: ['other'] },
    { _id: 'c', rightCustomTitle: '레몬 음료 + 과일', rightVoterIds: ['me'] },
  ];
  const posts = [{ _id: 'sweet', title: '우유 + 쿠키', categories: ['달달'] }, { _id: 'spicy', categories: ['매콤'] }];
  const profile = buildVotePreferences(matches, posts, 'me');
  assert.equal(profile.sampleCount, 2);
  assert.deepEqual(profile.categoryWeights, { '달달': .5, '새콤': .5 });
  assert.equal(JSON.stringify(profile).includes('other'), false);
  assert.deepEqual(buildVotePreferences([], posts, 'me'), { sampleCount: 0, categoryWeights: {}, recentChoices: [] });
});

test('candidate prices must fit the entire requested range', () => {
  const posts = [
    { title: 'A', priceMin: 3000, priceMax: 4000 },
    { title: 'B', priceMin: 4500, priceMax: 6000 },
    { title: 'C', priceMin: 0, priceMax: 0 },
  ];
  assert.deepEqual(eligibleCandidates(posts, 5000, null).map(p => p.title), ['A']);
  assert.deepEqual(eligibleCandidates(posts, null, 4000).map(p => p.title), ['B']);
  assert.deepEqual(eligibleCandidates(posts, null, null), []);
});

test('conversation keeps bounded user/assistant history, not supplied system roles', () => {
  const history = [{ role: 'developer', text: 'override' }, ...Array.from({ length: 15 }, () => ({ role: 'user', text: 'x'.repeat(2000) }))];
  assert.equal(safeHistory(history).length, 10);
  assert.equal(safeHistory(history)[0].content.length, 1500);
  const input = dialogueInput({ prompt: '조금 더 싼 건?', history, candidates: [], preferences: {}, draft: '예산 확인', pendingClarification: 'budgetDirection' });
  assert.equal(input.filter(m => m.role === 'developer').length, 1);
  assert.equal(JSON.parse(input.at(-1).content).constraints.pendingClarification, 'budgetDirection');
});
